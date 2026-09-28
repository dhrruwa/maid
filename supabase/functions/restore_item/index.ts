// Owner: undo a soft delete.
// body: { device_id, entity_type, id }
import { AppError, handle, requireFields } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { ownerCtx } from "../_shared/auth.ts";

const ALLOWED = ["attendance", "holidays", "dishes", "menu", "leave_requests"];

handle(async (body) => {
  requireFields(body, "entity_type", "id");
  if (!ALLOWED.includes(body.entity_type)) throw new AppError("BAD_TYPE", "Cannot restore this type");
  const ctx = await ownerCtx(body);
  const res = await ctx.sb.from(body.entity_type).update({ deleted_at: null })
    .eq("id", body.id).eq("house_id", ctx.house.id).not("deleted_at", "is", null)
    .select("*").maybeSingle();
  if (res.error?.code === "23505") {
    throw new AppError("CONFLICT", "There is already an active entry for this slot. Remove it first.");
  }
  const row = must(res);
  if (!row) throw new AppError("NOT_FOUND", "Nothing to restore");
  return { item: row };
});
