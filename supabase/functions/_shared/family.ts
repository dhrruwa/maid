// Family app: member logins (name + 4-digit PIN) and meal bookings.
// The pure helpers at the top have no database access and are unit-tested.

import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { must } from "./db.ts";
import { Settings } from "./auth.ts";
import { AppError, sha256Hex } from "./http.ts";
import { OffInfo, offSlotsRange } from "./menu.ts";
import { DishLine, menuFor, Slot, SLOTS, slotWindow } from "./pay.ts";
import { addDays, daysBetween } from "./time.ts";

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------

export const MAX_NAME = 40;
export const MAX_NOTE = 200;
/** Bookable dates: today .. today + BOOK_AHEAD_DAYS. */
export const BOOK_AHEAD_DAYS = 13;
export const MAX_FAILED_LOGINS = 5;
export const LOCK_MINUTES = 15;

/**
 * Salted PIN hash stored in members.pin_hash. Same formula as SQL seeding:
 * encode(extensions.digest('member-pin:' || id || ':' || pin, 'sha256'), 'hex')
 */
export function pinHash(memberId: string, pin: string): Promise<string> {
  return sha256Hex(`member-pin:${memberId}:${pin}`);
}

export const isPin = (pin: unknown): pin is string => typeof pin === "string" && /^\d{4}$/.test(pin);

/** A PIN from the request as a string ("0042" stays "0042"; a number is stringified). */
export function pinOf(v: unknown): string {
  if (typeof v === "number" && Number.isInteger(v) && v >= 0) return String(v);
  return typeof v === "string" ? v.trim() : "";
}

/** Trims and collapses inner whitespace: "  Asha   Rao " → "Asha Rao". */
export function cleanName(raw: unknown): string {
  return String(raw ?? "").normalize("NFC").trim().replace(/\s+/g, " ");
}

/** What login matching compares: lower(trim(name)) with inner spaces collapsed. */
export function nameKey(raw: unknown): string {
  return cleanName(raw).toLowerCase();
}

/** Characters that would act as wildcards in an ILIKE lookup (and have no place in a name). */
const LIKE_SPECIAL = /[%_*\\]/;

/** A name the owner may save: 1..40 characters, no wildcard characters. */
export function validName(raw: unknown): string {
  const name = cleanName(raw);
  const control = [...name].some((ch) => ch.charCodeAt(0) < 32);
  if (!name || name.length > MAX_NAME || LIKE_SPECIAL.test(name) || control) {
    throw new AppError("BAD_NAME", `Name must be 1–${MAX_NAME} characters`);
  }
  return name;
}

/** True when the name can be looked up with ILIKE as an exact (case-insensitive) match. */
export const likeSafe = (name: string) => name.length > 0 && name.length <= MAX_NAME && !LIKE_SPECIAL.test(name);

/** Booking note: trimmed, at most 200 characters, "" → null. */
export function cleanNote(raw: unknown): string | null {
  if (raw === undefined || raw === null) return null;
  const s = String(raw).trim().replace(/\s+/g, " ").slice(0, MAX_NOTE);
  return s || null;
}

/** The instant (ms) a slot's window starts on a date, Asia/Kolkata (UTC+5:30). */
export function slotCutoffMs(settings: Settings, date: string, slot: Slot): number {
  return Date.parse(date + "T00:00:00Z") + (slotWindow(settings, slot)[0] - 330) * 60000;
}

/** Can a member book / cancel this slot right now? */
export function slotOpen(
  settings: Settings,
  date: string,
  slot: Slot,
  off: OffInfo | null,
  nowMs: number,
): boolean {
  return !off && nowMs < slotCutoffMs(settings, date, slot);
}

/** Is `date` within today .. today+13? */
export function bookableDate(date: string, today: string): boolean {
  const d = daysBetween(today, date);
  return d >= 0 && d <= BOOK_AHEAD_DAYS;
}

// ---------------------------------------------------------------------------
// Bookings
// ---------------------------------------------------------------------------

export interface Person {
  name: string;
  note: string | null;
  name_kn: string | null;
  note_kn: string | null;
}

export interface Bookings {
  count: number;
  people: Person[];
}

interface BookingRow {
  id: string;
  member_id: string;
  date: string;
  slot: Slot;
  note: string | null;
  note_kn: string | null;
  members: MemberName | MemberName[] | null;
}

type MemberName = { name: string; name_kn: string | null };

export interface SlotBookings extends Bookings {
  /** member_id → that member's booking note (only members who booked). */
  byMember: Map<string, string | null>;
}

const emptySlot = (): SlotBookings => ({ count: 0, people: [], byMember: new Map() });

/** Active bookings per date and slot for a house, with names, sorted by name. */
export async function bookingsFor(
  sb: SupabaseClient,
  houseId: string,
  from: string,
  to: string,
): Promise<Map<string, Record<Slot, SlotBookings>>> {
  const rows = must(
    await sb.from("meal_bookings").select("id,member_id,date,slot,note,note_kn,members(name,name_kn)")
      .eq("house_id", houseId).is("cancelled_at", null)
      .gte("date", from).lte("date", to),
  ) as BookingRow[];
  const out = new Map<string, Record<Slot, SlotBookings>>();
  for (const r of rows) {
    if (!out.has(r.date)) out.set(r.date, { morning: emptySlot(), evening: emptySlot() });
    const m = Array.isArray(r.members) ? r.members[0] : r.members;
    const s = out.get(r.date)![r.slot];
    s.people.push({ name: m?.name ?? "?", note: r.note, name_kn: m?.name_kn ?? null, note_kn: r.note_kn });
    s.byMember.set(r.member_id, r.note);
    s.count++;
  }
  for (const day of out.values()) {
    for (const s of SLOTS) {
      day[s].people.sort((a, b) => a.name.localeCompare(b.name, "en", { sensitivity: "base" }));
    }
  }
  return out;
}

/** The public {count, people} part (without the member index). */
export const publicBookings = (b: SlotBookings | undefined): Bookings =>
  b ? { count: b.count, people: b.people } : { count: 0, people: [] };

/** One slot as the Family app sees it (the SLOT object of member_home / book_meal). */
export interface MemberSlot {
  items: DishLine[];
  off: OffInfo | null;
  cutoff: string;
  open: boolean;
  booked: boolean;
  note: string | null;
  bookings: Bookings;
}

export interface MemberDay {
  date: string;
  slots: Record<Slot, MemberSlot>;
}

/** Menu, off state, cutoff, the member's own booking and everyone's bookings for from..to. */
export async function memberDays(
  sb: SupabaseClient,
  houseId: string,
  settings: Settings,
  memberId: string,
  from: string,
  to: string,
  nowMs = Date.now(),
): Promise<MemberDay[]> {
  const [menus, off, bookings] = await Promise.all([
    menuFor(sb, houseId, from, to),
    offSlotsRange(sb, houseId, from, to),
    bookingsFor(sb, houseId, from, to),
  ]);
  const days: MemberDay[] = [];
  for (let date = from; date <= to; date = addDays(date, 1)) {
    const menu = menus.get(date) ?? { morning: [], evening: [] };
    const slots = {} as Record<Slot, MemberSlot>;
    for (const slot of SLOTS) {
      const o = off.get(date)?.[slot] ?? null;
      const b = bookings.get(date)?.[slot];
      slots[slot] = {
        items: menu[slot],
        off: o,
        cutoff: new Date(slotCutoffMs(settings, date, slot)).toISOString(),
        open: slotOpen(settings, date, slot, o, nowMs),
        booked: b?.byMember.has(memberId) ?? false,
        note: b?.byMember.get(memberId) ?? null,
        bookings: publicBookings(b),
      };
    }
    days.push({ date, slots });
  }
  return days;
}
