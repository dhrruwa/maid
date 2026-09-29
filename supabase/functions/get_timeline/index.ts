// Either phone: day-by-day visits for a date range (max 31 days): scan times,
// missed visits (the gaps), holidays and leave. Feeds the "This week" timeline.
// body: { device_id, from: 'YYYY-MM-DD', to: 'YYYY-MM-DD' }
import { AppError, handle, requireFields } from "../_shared/http.ts";
import { anyCtx } from "../_shared/auth.ts";
import { computeMonth, SlotInfo, SLOTS } from "../_shared/pay.ts";
import { addDays, daysBetween, isValidDate, monthOf, nowIst } from "../_shared/time.ts";

const slim = (i: SlotInfo) => ({
  state: i.state,
  amount: i.amount,
  scanned_at: i.attendance?.scanned_at ?? null,
  is_offline: i.attendance?.is_offline ?? false,
  is_manual: i.attendance?.is_manual ?? false,
});

handle(async (body) => {
  requireFields(body, "from", "to");
  const { from, to } = body;
  if (!isValidDate(from) || !isValidDate(to) || to < from) throw new AppError("BAD_DATE", "Invalid dates");
  if (daysBetween(from, to) > 31) throw new AppError("RANGE_TOO_LONG", "At most 31 days at a time");

  const ctx = await anyCtx(body);
  const now = nowIst();
  const months = [...new Set([monthOf(from), monthOf(to)])];
  const summaries = await Promise.all(months.map((m) => computeMonth(ctx, m, { now })));

  const wanted = new Set<string>();
  for (let d = from; d <= to; d = addDays(d, 1)) wanted.add(d);
  const days = summaries.flatMap((s) => s.days)
    .filter((d) => wanted.has(d.date))
    .sort((a, b) => (a.date < b.date ? -1 : 1))
    .map((d) => ({
      date: d.date,
      dow: d.dow,
      status: d.status,
      amount: d.amount,
      slots: { morning: slim(d.slots.morning), evening: slim(d.slots.evening) },
    }));

  let done = 0, missed = 0;
  for (const d of days) {
    for (const s of SLOTS) {
      if (d.slots[s].state === "done") done++;
      if (d.slots[s].state === "missed") missed++;
    }
  }

  const st = ctx.settings;
  return {
    from,
    to,
    now: now.iso,
    today: now.date,
    windows: {
      morning_start: st.morning_start,
      morning_end: st.morning_end,
      evening_start: st.evening_start,
      evening_end: st.evening_end,
    },
    done,
    missed,
    days,
  };
});
