// Either phone: PDF slip for a month. Returns a signed download URL (1 hour).
// Paid months reuse the frozen snapshot, so the slip never changes.
// body: { device_id, month: 'YYYY-MM' }
import { AppError, handle, requireFields } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { anyCtx } from "../_shared/auth.ts";
import { computeMonth } from "../_shared/pay.ts";
import { storeSlip } from "../_shared/slip.ts";
import { isValidMonth } from "../_shared/time.ts";

handle(async (body) => {
  requireFields(body, "month");
  if (!isValidMonth(body.month)) throw new AppError("BAD_MONTH", "month must be YYYY-MM");
  const ctx = await anyCtx(body);
  const summary = await computeMonth(ctx, body.month);

  if (summary.frozen) {
    const snap = must(
      await ctx.sb.from("monthly_snapshots").select("slip_url").eq("house_id", ctx.house.id)
        .eq("month", body.month).single(),
    ) as { slip_url: string | null };
    if (snap.slip_url) {
      const signed = await ctx.sb.storage.from("slips").createSignedUrl(snap.slip_url, 3600, {
        download: `payslip-${body.month}.pdf`,
      });
      if (!signed.error) {
        return { url: signed.data.signedUrl, month: body.month, paid: true, total: summary.payment?.total_amount };
      }
    }
    const { path, url } = await storeSlip(ctx, summary);
    must(
      await ctx.sb.from("monthly_snapshots").update({ slip_url: path }).eq("house_id", ctx.house.id)
        .eq("month", body.month),
    );
    return { url, month: body.month, paid: true, total: summary.payment?.total_amount };
  }

  const { url } = await storeSlip(ctx, summary);
  return { url, month: body.month, paid: false, total: summary.totals.earned };
});
