// Either phone: leave requests, newest first.
// body: { device_id, status?: 'pending' | ..., limit? }
import { handle } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { anyCtx } from "../_shared/auth.ts";

handle(async (body) => {
  const ctx = await anyCtx(body);
  let q = ctx.sb.from("leave_requests")
    .select("id,date,slot,reason,status,decided_at,created_at")
    .eq("house_id", ctx.house.id).is("deleted_at", null);
  if (body.status) q = q.eq("status", body.status);
  const rows = must(
    await q.order("created_at", { ascending: false }).limit(Math.min(Number(body.limit) || 200, 500)),
  );
  return { leaves: rows };
});
