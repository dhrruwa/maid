// Owner Home: live salary, today, today's menu, month counts, pending leave,
// "salary due" banner.
import { handle } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { ownerCtx, publicCook, publicHouse } from "../_shared/auth.ts";
import { computeMonth, liveSalary } from "../_shared/pay.ts";
import { offSlots } from "../_shared/menu.ts";
import { nowIst, prevMonth, toIst } from "../_shared/time.ts";

handle(async (body) => {
  const ctx = await ownerCtx(body);
  const now = nowIst();
  const current = now.date.slice(0, 7);
  const last = prevMonth(current);
  const startMonth = toIst(new Date(ctx.house.created_at)).date.slice(0, 7);

  const [salary, pending, off] = await Promise.all([
    liveSalary(ctx),
    ctx.sb.from("leave_requests").select("id,date,slot,reason,status,created_at")
      .eq("house_id", ctx.house.id).eq("status", "pending").is("deleted_at", null)
      .order("date"),
    offSlots(ctx.sb, ctx.house.id, now.date),
  ]);

  let salaryDue = null;
  if (last >= startMonth) {
    const s = await computeMonth(ctx, last, { now });
    if (!s.payment && s.totals.earned > 0) salaryDue = { month: last, total: s.totals.earned };
  }

  return {
    house: publicHouse(ctx.house, false),
    cook: publicCook(ctx.cook),
    salary,
    today: salary.today_info,
    today_off: off,
    pending_leaves: must(pending),
    salary_due: salaryDue,
    now: now.iso,
  };
});
