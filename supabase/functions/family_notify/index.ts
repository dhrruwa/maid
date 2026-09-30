// Scheduled every 10 min. Notifications for the Family app:
// 1. Menu set or changed: once the owner's edits to a meal have settled (no
//    change for 5 minutes), every linked member hears about it, while the
//    meal can still be booked. Several meals changed at once (copy menu) make
//    one notification, not one each.
// 2. Booking reminder: 90 minutes before a meal's booking closes, members who
//    have not booked it are reminded. A reminder that would land at night
//    (10 PM – 7 AM) goes out at 9 PM the evening before instead.
// Each is sent once (sent_reminders; a menu notice again after a later change).
import { handle, requireCronSecret } from "../_shared/http.ts";
import { db, must } from "../_shared/db.ts";
import { House, Settings } from "../_shared/auth.ts";
import { bookingsFor, BOOK_AHEAD_DAYS, slotCutoffMs } from "../_shared/family.ts";
import { offSlotsRange } from "../_shared/menu.ts";
import { menuFor, Slot, SLOTS, slotWindow } from "../_shared/pay.ts";
import { addDays, minToLabel, nowIst, shortDate, toIst } from "../_shared/time.ts";
import { sendPush } from "../_shared/fcm.ts";

const SETTLE_MS = 5 * 60000;
const REMIND_BEFORE_MS = 90 * 60000;
const WINDOW_MS = 20 * 60000; // > the 10-minute schedule, so a late run still sends
const QUIET_FROM = 22 * 60; // 10 PM
const QUIET_TO = 7 * 60; // 7 AM
const EVENING_BEFORE = 21 * 60; // 9 PM

interface Member {
  id: string;
  name: string;
  fcm_token: string;
}

const slotName = (s: Slot) => (s === "morning" ? "morning" : "evening");
const weekday = (date: string) =>
  ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][new Date(date + "T00:00:00Z").getUTCDay()];

function dayName(date: string, today: string): string {
  if (date === today) return "today";
  if (date === addDays(today, 1)) return "tomorrow";
  return `${weekday(date)} ${shortDate(date)}`;
}

/** When to remind about a meal whose booking closes at cutoffMs. */
function remindAtMs(cutoffMs: number): number {
  const at = cutoffMs - REMIND_BEFORE_MS;
  const ist = toIst(new Date(at));
  const midnightUtc = Date.parse(ist.date + "T00:00:00Z") - 330 * 60000;
  if (ist.minutes >= QUIET_FROM) return midnightUtc + EVENING_BEFORE * 60000;
  if (ist.minutes < QUIET_TO) return midnightUtc - (24 * 60 - EVENING_BEFORE) * 60000;
  return at;
}

handle(async (_body, req) => {
  requireCronSecret(req);
  const sb = db("system");
  const now = nowIst();
  const nowMs = Date.parse(now.iso);
  const today = now.date;
  const last = addDays(today, BOOK_AHEAD_DAYS);
  const houses = must(await sb.from("house").select("*")) as House[];
  const sent: string[] = [];

  for (const house of houses) {
    const members = (must(
      await sb.from("members").select("id,name,fcm_token").eq("house_id", house.id).eq("active", true)
        .not("device_id", "is", null).not("fcm_token", "is", null),
    ) as Member[]);
    if (!members.length) continue;
    const settings = must(await sb.from("settings").select("*").eq("house_id", house.id).single()) as Settings;

    const [menus, off, bookings, changes, notices] = await Promise.all([
      menuFor(sb, house.id, today, last),
      offSlotsRange(sb, house.id, today, last),
      bookingsFor(sb, house.id, today, last),
      // Every menu row touched lately, removed ones too (a removal is a change).
      sb.from("menu").select("date,slot,updated_at").eq("house_id", house.id)
        .gte("date", today).lte("date", last).gte("updated_at", new Date(nowMs - 3 * 86400000).toISOString()),
      sb.from("sent_reminders").select("kind,day,updated_at").eq("house_id", house.id)
        .gte("day", addDays(today, -1)).like("kind", "family_%"),
    ]);
    const sentAt = new Map<string, number>();
    for (const n of must(notices) as { kind: string; day: string; updated_at: string }[]) {
      sentAt.set(`${n.kind}|${n.day}`, Date.parse(n.updated_at));
    }
    const isOpen = (date: string, slot: Slot) =>
      !off.get(date)?.[slot] && slotCutoffMs(settings, date, slot) > nowMs;
    const dishes = (date: string, slot: Slot) =>
      (menus.get(date)?.[slot] ?? []).map((d) => d.name).join(", ");
    const closes = (slot: Slot) => minToLabel(slotWindow(settings, slot)[0]); // booking closes when cooking starts
    const mark = async (kind: string, day: string) =>
      must(await sb.from("sent_reminders").upsert({ house_id: house.id, kind, day, updated_at: new Date().toISOString() }));

    // 1. Menu changes that have settled.
    const lastChange = new Map<string, number>();
    for (const r of must(changes) as { date: string; slot: Slot; updated_at: string }[]) {
      const key = `${r.date}|${r.slot}`;
      lastChange.set(key, Math.max(lastChange.get(key) ?? 0, Date.parse(r.updated_at)));
    }
    const changed: { date: string; slot: Slot }[] = [];
    for (const [key, at] of lastChange) {
      const [date, slot] = key.split("|") as [string, Slot];
      if (nowMs - at < SETTLE_MS) continue; // the owner may still be editing
      if ((sentAt.get(`family_menu_${slot}|${date}`) ?? 0) >= at) continue; // already told
      await mark(`family_menu_${slot}`, date);
      if (isOpen(date, slot) && dishes(date, slot)) changed.push({ date, slot });
    }
    changed.sort((a, b) => (a.date + a.slot < b.date + b.slot ? -1 : 1));
    if (changed.length) {
      const one = changed[0];
      const title = changed.length === 1
        ? `Menu for ${dayName(one.date, today)} ${slotName(one.slot)}`
        : `${changed.length} menus updated`;
      const body = changed.length === 1
        ? `${dishes(one.date, one.slot)}. Book before ${closes(one.slot)} if you're eating.`
        : `${changed.map((c) => `${dayName(c.date, today)} ${slotName(c.slot)}`).join(", ")}. Tap to see them and book.`;
      for (const m of members) {
        if (await sendPush(m.fcm_token, title, body, { kind: "family_menu", date: one.date, slot: one.slot })) {
          sent.push(`menu:${m.id}`);
        }
      }
    }

    // 2. Booking reminders for members who have not booked.
    for (const date of [today, addDays(today, 1), addDays(today, 2)]) {
      for (const slot of SLOTS) {
        if (!isOpen(date, slot)) continue;
        const at = remindAtMs(slotCutoffMs(settings, date, slot));
        if (nowMs < at || nowMs >= at + WINDOW_MS) continue;
        const booked = bookings.get(date)?.[slot]?.byMember ?? new Map();
        const menu = dishes(date, slot);
        for (const m of members) {
          if (booked.has(m.id)) continue;
          const kind = `family_book_${slot}_${m.id}`;
          if (sentAt.has(`${kind}|${date}`)) continue;
          const claim = await sb.from("sent_reminders").insert({ house_id: house.id, kind, day: date });
          if (claim.error) continue; // another run got it
          const title = `Eating ${dayName(date, today)} ${slotName(slot)}?`;
          const body = `${menu ? `${menu}. ` : ""}Book before ${closes(slot)} so the cook knows how many to cook for.`;
          if (await sendPush(m.fcm_token, title, body, { kind: "family_book", date, slot })) {
            sent.push(`book:${m.id}:${date}:${slot}`);
          }
        }
      }
    }
  }
  return { sent };
});
