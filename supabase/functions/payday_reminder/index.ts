// Scheduled daily at 9 AM IST. On the 1st: "Salary due today: ₹X for September".
// On the 4th, if still unpaid: reminder.
import { handle, requireCronSecret } from "../_shared/http.ts";
import { db, must } from "../_shared/db.ts";
import { activeCook, Ctx, House, Settings } from "../_shared/auth.ts";
import { computeMonth } from "../_shared/pay.ts";
import { monthName, nowIst, prevMonth, toIst } from "../_shared/time.ts";
import { notifyOwner } from "../_shared/notify.ts";

handle(async (body, req) => {
  requireCronSecret(req);
  const sb = db("system");
  const now = nowIst();
  const day = Number(now.date.slice(8, 10));
  if (day !== 1 && day !== 4 && !body.force) return { skipped: "not the 1st or 4th" };

  const month = prevMonth(now.date.slice(0, 7));
  const houses = must(await sb.from("house").select("*")) as House[];
  const sent: string[] = [];

  for (const house of houses) {
    if (toIst(new Date(house.created_at)).date.slice(0, 7) > month) continue;
    const settings = must(await sb.from("settings").select("*").eq("house_id", house.id).single()) as Settings;
    const ctx: Ctx = { role: "owner", sb, house, settings, cook: await activeCook(sb, house.id) };
    const s = await computeMonth(ctx, month, { now });
    if (s.payment || s.totals.earned <= 0) continue;

    const kind = day === 1 ? "payday" : "payday_reminder";
    const claim = await sb.from("sent_reminders").insert({ house_id: house.id, kind, day: now.date });
    if (claim.error) continue;

    const title = day === 1 ? "Salary due today" : "Reminder: salary not marked as paid";
    await notifyOwner(ctx, "payday", title, `₹${s.totals.earned} for ${monthName(month)}`, { month });
    sent.push(house.id);
  }
  return { month, sent };
});
