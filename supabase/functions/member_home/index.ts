// Family app: the next days' menu with booking state.
// body: { device_id, days?: 7 (1..14), fcm_token? }
// → { member: { id, name }, house_name, today,
//     days: [{ date, slots: { morning: SLOT, evening: SLOT } }] }
// SLOT = { items, off, cutoff, open, booked, note, bookings: { count, people: [{ name, note }] } }
import { handle } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { memberCtx } from "../_shared/auth.ts";
import { BOOK_AHEAD_DAYS, memberDays } from "../_shared/family.ts";
import { addDays, nowIst } from "../_shared/time.ts";

handle(async (body) => {
  const ctx = await memberCtx(body);
  const member = ctx.member!;
  const count = Math.min(Math.max(Math.trunc(Number(body.days)) || 7, 1), BOOK_AHEAD_DAYS + 1);
  const now = nowIst();

  // Keep the push token fresh (it can rotate after login).
  const token = typeof body.fcm_token === "string" && body.fcm_token ? body.fcm_token : null;
  const refresh = token && token !== member.fcm_token
    ? ctx.sb.from("members").update({ fcm_token: token }).eq("id", member.id).then(must)
    : null;

  const [days] = await Promise.all([
    memberDays(ctx.sb, ctx.house.id, ctx.settings, member.id, now.date, addDays(now.date, count - 1),
      Date.parse(now.iso)),
    refresh,
  ]);
  return {
    member: { id: member.id, name: member.name },
    house_name: ctx.house.name,
    today: now.date,
    days,
  };
});
