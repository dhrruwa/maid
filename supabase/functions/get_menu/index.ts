// Owner, maid or family member: menu for one date, with holiday/leave info
// and who booked each slot.
// body: { device_id, date }
// → { date, morning: { items, off, bookings: { count, people: [{ name, note }] } }, evening: {…} }
import { AppError, handle, requireFields } from "../_shared/http.ts";
import { readerCtx } from "../_shared/auth.ts";
import { offSlots } from "../_shared/menu.ts";
import { menuFor } from "../_shared/pay.ts";
import { bookingsFor, publicBookings } from "../_shared/family.ts";
import { isValidDate } from "../_shared/time.ts";

handle(async (body) => {
  requireFields(body, "date");
  const ctx = await readerCtx(body);
  if (!isValidDate(body.date)) throw new AppError("BAD_DATE", "Invalid date");
  const date = body.date as string;
  const [menus, off, bookings] = await Promise.all([
    menuFor(ctx.sb, ctx.house.id, date, date),
    offSlots(ctx.sb, ctx.house.id, date),
    bookingsFor(ctx.sb, ctx.house.id, date, date),
  ]);
  const m = menus.get(date) ?? { morning: [], evening: [] };
  const b = bookings.get(date);
  return {
    date,
    morning: { items: m.morning, off: off.morning, bookings: publicBookings(b?.morning) },
    evening: { items: m.evening, off: off.evening, bookings: publicBookings(b?.evening) },
  };
});
