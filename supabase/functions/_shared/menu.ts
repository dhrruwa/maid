import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { must } from "./db.ts";
import { Ctx } from "./auth.ts";
import { AppError } from "./http.ts";
import { addDays, nowIst } from "./time.ts";
import { menuFor, Slot, slotExpected } from "./pay.ts";
import { KN, notifyMaid } from "./notify.ts";

/** Returns the 11-char video id, or null if it is not a YouTube link. */
export function youtubeId(url: string): string | null {
  const m = url.trim().match(
    /^(?:https?:\/\/)?(?:www\.|m\.|music\.)?(?:youtube\.com\/(?:watch\?(?:.*&)?v=|shorts\/|embed\/|live\/|v\/)|youtu\.be\/)([A-Za-z0-9_-]{11})/,
  );
  return m ? m[1] : null;
}

export function cleanYoutube(url: unknown): string | null {
  if (url === undefined || url === null || String(url).trim() === "") return null;
  if (!youtubeId(String(url))) throw new AppError("BAD_YOUTUBE", "This is not a YouTube link");
  return String(url).trim();
}

export interface OffInfo {
  type: "holiday" | "leave" | "not_needed";
  paid: boolean;
  note: string | null;
}

/** Is this slot off (holiday / approved leave / weekend evening)? */
export async function offSlots(
  sb: SupabaseClient,
  houseId: string,
  date: string,
): Promise<Record<Slot, OffInfo | null>> {
  const [hol, lv] = await Promise.all([
    sb.from("holidays").select("slot,paid,note").eq("house_id", houseId).eq("date", date)
      .is("deleted_at", null),
    sb.from("leave_requests").select("slot,status,reason").eq("house_id", houseId).eq("date", date)
      .in("status", ["approved_paid", "approved_unpaid"]).is("deleted_at", null),
  ]);
  const holidays = must(hol) as { slot: string; paid: boolean; note: string | null }[];
  const leaves = must(lv) as { slot: string; status: string; reason: string | null }[];
  const out = {} as Record<Slot, OffInfo | null>;
  for (const slot of ["morning", "evening"] as Slot[]) {
    const h = holidays.find((x) => x.slot === "full" || x.slot === slot);
    const l = leaves.find((x) => x.slot === "full" || x.slot === slot);
    out[slot] = h
      ? { type: "holiday", paid: h.paid, note: h.note }
      : l
      ? { type: "leave", paid: l.status === "approved_paid", note: l.reason }
      : !slotExpected(date, slot)
      ? { type: "not_needed", paid: false, note: null }
      : null;
  }
  return out;
}

/**
 * "Tomorrow morning: Palak Paneer, Chapati" to the maid, if any of the changed
 * dates is today or tomorrow and the owner has menu notifications on.
 */
export async function notifyMenuChange(ctx: Ctx, changed: { date: string; slot: Slot }[]) {
  if (!ctx.settings.notify_menu) return;
  const today = nowIst().date;
  const tomorrow = addDays(today, 1);
  const relevant = changed.filter((c) => c.date === today || c.date === tomorrow);
  if (!relevant.length) return;

  const menus = await menuFor(ctx.sb, ctx.house.id, today, tomorrow);
  const en: string[] = [];
  const kn: string[] = [];
  const seen = new Set<string>();
  for (const c of relevant) {
    const key = `${c.date}|${c.slot}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const dishes = menus.get(c.date)?.[c.slot] ?? [];
    const names = dishes.length ? dishes.map((d) => d.name).join(", ") : "—";
    const dayEn = c.date === today ? "Today" : "Tomorrow";
    const dayKn = c.date === today ? KN.today : KN.tomorrow;
    en.push(`${dayEn} ${c.slot}: ${names}`);
    kn.push(`${dayKn} ${c.slot === "morning" ? KN.morning : KN.evening}: ${names}`);
  }
  await notifyMaid(ctx, {
    en: { title: "What to cook", body: en.join("\n") },
    kn: { title: "ಏನು ಅಡುಗೆ ಮಾಡಬೇಕು", body: kn.join("\n") },
  }, { kind: "menu" });
}
