// Maid phone: ask for leave.
// body: { device_id, date, slot: 'morning'|'evening'|'full', reason? }
import { AppError, handle, requireFields } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { maidCtx } from "../_shared/auth.ts";
import { isValidDate, nowIst, shortDate } from "../_shared/time.ts";
import { notifyOwner, slotEn } from "../_shared/notify.ts";

handle(async (body) => {
  requireFields(body, "device_id", "date", "slot");
  const ctx = await maidCtx(body);
  const { sb, house } = ctx;
  const date = body.date as string;
  if (!isValidDate(date)) throw new AppError("BAD_DATE", "Invalid date");
  if (date < nowIst().date) throw new AppError("PAST_DATE", "Pick today or a later date");
  if (!["morning", "evening", "full"].includes(body.slot)) throw new AppError("BAD_SLOT", "Invalid slot");

  const open = must(
    await sb.from("leave_requests").select("id,slot").eq("house_id", house.id).eq("date", date)
      .in("status", ["pending", "approved_paid", "approved_unpaid"]).is("deleted_at", null),
  ) as { slot: string }[];
  if (open.some((l) => l.slot === "full" || body.slot === "full" || l.slot === body.slot)) {
    throw new AppError("LEAVE_EXISTS", "You already asked for leave on this day");
  }

  const reason = body.reason ? String(body.reason).slice(0, 300) : null;
  const row = must(
    await sb.from("leave_requests").insert({
      house_id: house.id,
      device_id: body.device_id,
      date,
      slot: body.slot,
      reason,
    }).select("*").single(),
  );

  await notifyOwner(
    ctx,
    "leave",
    "New leave request",
    `${ctx.cook!.name}: ${shortDate(date)} (${slotEn(body.slot)})${reason ? ` – ${reason}` : ""}`,
    { leave_id: row.id },
  );
  return { leave: row };
});
