// Either phone: one row per month since setup – visits, total, paid or not.
import { handle } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { anyCtx } from "../_shared/auth.ts";
import { computeMonth } from "../_shared/pay.ts";
import { nextMonth, nowIst, toIst } from "../_shared/time.ts";

handle(async (body) => {
  const ctx = await anyCtx(body);
  const now = nowIst();
  const current = now.date.slice(0, 7);
  const start = toIst(new Date(ctx.house.created_at)).date.slice(0, 7);

  const months: string[] = [];
  for (let m = start; m <= current; m = nextMonth(m)) months.push(m);

  // Slip list and every month's summary load in one parallel batch.
  const [snapsRes, summaries] = await Promise.all([
    ctx.sb.from("monthly_snapshots").select("month,slip_url").eq("house_id", ctx.house.id),
    Promise.allSettled(months.map((month) => computeMonth(ctx, month, { now }))),
  ]);
  const snaps = must(snapsRes) as { month: string; slip_url: string | null }[];

  const rows = months.map((month, i) => {
    const r = summaries[i];
    if (r.status === "rejected") throw r.reason;
    const s = r.value;
    return {
      month,
      visits: s.counts.visits_done,
      missed: s.counts.missed,
      total: s.totals.earned,
      paid: !!s.payment,
      paid_on: s.payment?.paid_on ?? null,
      paid_amount: s.payment?.total_amount ?? null,
      has_slip: !!snaps.find((x) => x.month === month)?.slip_url,
      is_current: month === current,
    };
  });
  return { months: rows.reverse() };
});
