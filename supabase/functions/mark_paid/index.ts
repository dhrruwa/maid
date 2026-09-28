// Owner: mark a month's salary as paid. Freezes the month summary + slip and
// tells the maid.
// body: { device_id, month: 'YYYY-MM', paid_on?: 'YYYY-MM-DD' }
import { AppError, handle, requireFields } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { ownerCtx } from "../_shared/auth.ts";
import { computeMonth } from "../_shared/pay.ts";
import { storeSlip } from "../_shared/slip.ts";
import { isValidDate, isValidMonth, monthName, nowIst, shortDate, toIst } from "../_shared/time.ts";
import { notifyMaid } from "../_shared/notify.ts";

handle(async (body) => {
  requireFields(body, "month");
  const month = body.month as string;
  if (!isValidMonth(month)) throw new AppError("BAD_MONTH", "month must be YYYY-MM");
  const ctx = await ownerCtx(body);
  const { sb, house } = ctx;
  const now = nowIst();
  if (month >= now.date.slice(0, 7)) {
    throw new AppError("MONTH_NOT_OVER", "You can mark a month as paid once it is over");
  }
  if (month < toIst(new Date(house.created_at)).date.slice(0, 7)) {
    throw new AppError("BEFORE_SETUP", "This month is before the app was set up");
  }
  const paidOn = isValidDate(body.paid_on) ? body.paid_on as string : now.date;

  const exists = must(
    await sb.from("payments").select("id").eq("house_id", house.id).eq("month", month).maybeSingle(),
  );
  if (exists) throw new AppError("ALREADY_PAID", "This month is already marked as paid");

  const summary = await computeMonth(ctx, month, { now, ignoreSnapshot: true });
  const total = summary.totals.earned;

  must(await sb.from("payments").insert({ house_id: house.id, month, total_amount: total, paid_on: paidOn }));

  const frozen = { ...summary, frozen: true, payment: { paid_on: paidOn, total_amount: total } };
  must(await sb.from("monthly_snapshots").insert({
    house_id: house.id,
    month,
    rates_used: summary.rates,
    summary: frozen,
  }));

  let slipUrl: string | null = null;
  try {
    const { path, url } = await storeSlip(ctx, frozen);
    slipUrl = url;
    must(await sb.from("monthly_snapshots").update({ slip_url: path }).eq("house_id", house.id).eq("month", month));
  } catch (e) {
    console.error("slip generation failed", e); // payment is saved; slip can be regenerated
  }

  const name = monthName(month);
  await notifyMaid(ctx, {
    en: { title: "Salary paid ✅", body: `${name} salary ₹${total} paid on ${shortDate(paidOn)}` },
    kn: { title: "ಸಂಬಳ ಪಾವತಿಸಲಾಗಿದೆ ✅", body: `${name} ಸಂಬಳ ₹${total} ${shortDate(paidOn)} ರಂದು ಪಾವತಿಸಲಾಗಿದೆ` },
  }, { kind: "paid", month });

  return { month, total, paid_on: paidOn, slip_url: slipUrl };
});
