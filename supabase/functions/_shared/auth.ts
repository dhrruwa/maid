import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { Actor, db, must } from "./db.ts";
import { AppError, Body } from "./http.ts";

export interface House {
  id: string;
  name: string;
  lat: number | null;
  lng: number | null;
  radius_m: number;
  qr_token: string;
  owner_pin_hash: string | null;
  owner_device_id: string;
  owner_fcm_token: string | null;
  created_at: string;
}

export interface Settings {
  house_id: string;
  weekday_rate: number;
  weekend_rate: number;
  paid_off_rate: number; // a paid holiday / paid leave, per meal
  morning_start: string;
  morning_end: string;
  evening_start: string;
  evening_end: string;
  notify_scan: boolean;
  notify_leave: boolean;
  notify_offline: boolean;
  notify_payday: boolean;
  notify_menu: boolean;
}

export interface CookDevice {
  id: string;
  house_id: string;
  device_id: string;
  name: string;
  fcm_token: string | null;
  lang: "en" | "kn";
  paired_at: string;
  active: boolean;
}

/** A family member (Family app). pin_hash is never loaded into a context. */
export interface Member {
  id: string;
  house_id: string;
  name: string;
  device_id: string | null;
  fcm_token: string | null;
  linked_at: string | null;
  active: boolean;
  created_at: string;
}

/** Member columns that are safe to load (everything but pin_hash / lockout counters). */
export const MEMBER_COLS = "id,house_id,name,device_id,fcm_token,linked_at,active,created_at";

export interface Ctx {
  role: "owner" | "maid" | "member";
  sb: SupabaseClient;
  house: House;
  settings: Settings;
  cook: CookDevice | null; // the active maid phone (for the owner and members too, if paired)
  member?: Member | null; // the logged-in family member (role "member" only)
}

function deviceId(body: Body): string {
  const id = body.device_id;
  if (typeof id !== "string" || id.length < 16) {
    throw new AppError("NO_DEVICE", "device_id is required", {}, 401);
  }
  return id;
}

// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;

/** An embedded one-to-one row comes back as an object (or a 1-element array on older PostgREST). */
function one<T>(v: unknown): T | null {
  if (Array.isArray(v)) return (v[0] ?? null) as T | null;
  return (v ?? null) as T | null;
}

/** Same guarantee as the old `.single()` settings lookup: every house has a settings row. */
function requireSettings(v: unknown): Settings {
  const s = one<Settings>(v);
  if (!s) throw new Error("JSON object requested, multiple (or no) rows returned");
  return s;
}

export async function activeCook(sb: SupabaseClient, houseId: string): Promise<CookDevice | null> {
  return must(
    await sb.from("cook_device").select("*").eq("house_id", houseId).eq("active", true)
      .order("paired_at", { ascending: false }).limit(1).maybeSingle(),
  ) as CookDevice | null;
}

/**
 * Owner phone. One round trip: the house row with its settings and the
 * newest active maid phone embedded.
 */
export async function ownerCtx(body: Body): Promise<Ctx> {
  const id = deviceId(body);
  const sb = db("owner");
  const row = must(
    await sb.from("house").select("*, settings(*), cook_device(*)")
      .eq("owner_device_id", id)
      .eq("cook_device.active", true)
      .order("paired_at", { ascending: false, referencedTable: "cook_device" })
      .limit(1, { referencedTable: "cook_device" })
      .maybeSingle(),
  ) as Row | null;
  if (!row) throw new AppError("NOT_OWNER", "This phone is not the owner phone", {}, 401);
  const { settings, cook_device, ...house } = row;
  return {
    role: "owner",
    sb,
    house: house as House,
    settings: requireSettings(settings),
    cook: one<CookDevice>(cook_device),
  };
}

/**
 * Maid phone. One round trip: the active cook_device row with its house and
 * the house settings embedded.
 */
export async function maidCtx(body: Body): Promise<Ctx> {
  const id = deviceId(body);
  const sb = db("maid");
  const row = must(
    await sb.from("cook_device").select("*, house(*, settings(*))").eq("device_id", id).eq("active", true)
      .order("paired_at", { ascending: false }).limit(1).maybeSingle(),
  ) as Row | null;
  if (!row) throw new AppError("NOT_PAIRED", "This phone is not paired", {}, 401);
  const { house: houseRow, ...cook } = row;
  const h = one<Row>(houseRow);
  if (!h) throw new Error("JSON object requested, multiple (or no) rows returned");
  const { settings, ...house } = h;
  return { role: "maid", sb, house: house as House, settings: requireSettings(settings), cook: cook as CookDevice };
}

/**
 * Either the owner phone or the paired maid phone. Both lookups run in
 * parallel; the owner wins, exactly as the old owner-then-maid order did.
 */
export async function anyCtx(body: Body): Promise<Ctx> {
  deviceId(body);
  const [owner, maid] = await Promise.allSettled([ownerCtx(body), maidCtx(body)]);
  if (owner.status === "fulfilled") return owner.value;
  const e = owner.reason;
  if (!(e instanceof AppError && e.code === "NOT_OWNER")) throw e;
  if (maid.status === "fulfilled") return maid.value;
  throw maid.reason;
}

/**
 * Family app phone. One round trip: the active member bound to this device
 * with the house, its settings and the newest active maid phone embedded.
 */
export async function memberCtx(body: Body): Promise<Ctx> {
  const id = deviceId(body);
  const sb = db("member");
  const row = must(
    await sb.from("members").select(`${MEMBER_COLS}, house(*, settings(*), cook_device(*))`)
      .eq("device_id", id).eq("active", true)
      .eq("house.cook_device.active", true)
      .order("paired_at", { ascending: false, referencedTable: "house.cook_device" })
      .limit(1, { referencedTable: "house.cook_device" })
      .limit(1).maybeSingle(),
  ) as Row | null;
  if (!row) {
    throw new AppError("NOT_MEMBER", "This phone is not logged in as a family member", {}, 401);
  }
  const { house: houseRow, ...member } = row;
  const h = one<Row>(houseRow);
  if (!h) throw new Error("JSON object requested, multiple (or no) rows returned");
  const { settings, cook_device, ...house } = h;
  return {
    role: "member",
    sb,
    house: house as House,
    settings: requireSettings(settings),
    cook: one<CookDevice>(cook_device),
    member: member as Member,
  };
}

const isAuthMiss = (r: PromiseSettledResult<Ctx>, code: string) =>
  r.status === "rejected" && r.reason instanceof AppError && r.reason.code === code;

/**
 * Anyone who may read the menu: the owner phone, the paired maid phone or a
 * logged-in family member. All three lookups run in parallel; owner wins,
 * then maid, then member. When none matches, the maid's NOT_PAIRED error is
 * thrown (what the maid and owner apps already handle).
 */
export async function readerCtx(body: Body): Promise<Ctx> {
  deviceId(body);
  const [owner, maid, member] = await Promise.allSettled([
    ownerCtx(body),
    maidCtx(body),
    memberCtx(body),
  ]);
  if (owner.status === "fulfilled") return owner.value;
  if (!isAuthMiss(owner, "NOT_OWNER")) throw (owner as PromiseRejectedResult).reason;
  if (maid.status === "fulfilled") return maid.value;
  if (!isAuthMiss(maid, "NOT_PAIRED")) throw (maid as PromiseRejectedResult).reason;
  if (member.status === "fulfilled") return member.value;
  if (!isAuthMiss(member, "NOT_MEMBER")) throw (member as PromiseRejectedResult).reason;
  throw (maid as PromiseRejectedResult).reason;
}

export function actorOf(ctx: Ctx): Actor {
  return ctx.role;
}

/** House fields safe to send to the owner app (no PIN hash / recovery hash). */
export function publicHouse(h: House, withQr = true) {
  return {
    id: h.id,
    name: h.name,
    lat: h.lat,
    lng: h.lng,
    radius_m: h.radius_m,
    qr_token: withQr ? h.qr_token : undefined,
    owner_pin_hash: h.owner_pin_hash,
    created_at: h.created_at,
  };
}

export function publicCook(c: CookDevice | null) {
  return c ? { id: c.id, name: c.name, paired_at: c.paired_at, lang: c.lang } : null;
}
