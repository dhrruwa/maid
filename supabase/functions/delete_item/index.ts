// Owner: soft delete a holiday, dish, menu line or leave request.
// (Attendance entries go through owner_edit_attendance.)
// body: { device_id, entity_type, id, note? }
import { AppError, handle, requireFields } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { ownerCtx } from "../_shared/auth.ts";
import { shortDate } from "../_shared/time.ts";
import { notifyMaid, slotEn, slotKn } from "../_shared/notify.ts";

const ALLOWED = ["holidays", "dishes", "menu", "leave_requests"];

handle(async (body) => {
  requireFields(body, "entity_type", "id");
  if (!ALLOWED.includes(body.entity_type)) throw new AppError("BAD_TYPE", "Cannot delete this type");
  const ctx = await ownerCtx(body);
  const patch: Record<string, unknown> = { deleted_at: new Date().toISOString() };
  if (body.note && ["holidays"].includes(body.entity_type)) patch.note = String(body.note).slice(0, 300);

  const row = must(
    await ctx.sb.from(body.entity_type).update(patch).eq("id", body.id).eq("house_id", ctx.house.id)
      .is("deleted_at", null).select("*").maybeSingle(),
  ) as Record<string, string> | null;
  if (!row) throw new AppError("NOT_FOUND", "Item not found");

  if (body.entity_type === "holidays") {
    await notifyMaid(ctx, {
      en: { title: "Holiday cancelled – please come", body: `${shortDate(row.date)} (${slotEn(row.slot)})` },
      kn: { title: "ರಜೆ ರದ್ದು – ದಯವಿಟ್ಟು ಬನ್ನಿ", body: `${shortDate(row.date)} (${slotKn(row.slot)})` },
    }, { kind: "holiday" });
  }
  return { item: row };
});
