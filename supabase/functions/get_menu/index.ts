// Either phone: menu for one date, with holiday/leave info per slot.
// body: { device_id, date }
import { AppError, handle, requireFields } from "../_shared/http.ts";
import { anyCtx } from "../_shared/auth.ts";
import { offSlots } from "../_shared/menu.ts";
import { menuFor } from "../_shared/pay.ts";
import { isValidDate } from "../_shared/time.ts";

handle(async (body) => {
  requireFields(body, "date");
  const ctx = await anyCtx(body);
  if (!isValidDate(body.date)) throw new AppError("BAD_DATE", "Invalid date");
  const date = body.date as string;
  const [menus, off] = await Promise.all([
    menuFor(ctx.sb, ctx.house.id, date, date),
    offSlots(ctx.sb, ctx.house.id, date),
  ]);
  const m = menus.get(date) ?? { morning: [], evening: [] };
  return {
    date,
    morning: { items: m.morning, off: off.morning },
    evening: { items: m.evening, off: off.evening },
  };
});
