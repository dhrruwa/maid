// Either phone: every day of a month with slot states, amounts, menu, counts
// and payment status. Paid months are frozen snapshots.
// body: { device_id, month: 'YYYY-MM' }
import { AppError, handle, requireFields } from "../_shared/http.ts";
import { anyCtx } from "../_shared/auth.ts";
import { computeMonth } from "../_shared/pay.ts";
import { isValidMonth } from "../_shared/time.ts";

handle(async (body) => {
  requireFields(body, "month");
  if (!isValidMonth(body.month)) throw new AppError("BAD_MONTH", "month must be YYYY-MM");
  const ctx = await anyCtx(body);
  return { summary: await computeMonth(ctx, body.month) };
});
