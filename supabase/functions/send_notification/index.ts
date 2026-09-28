// Internal: send a push to the owner or maid of a house. Protected by CRON_SECRET.
// header x-cron-secret; body: { house_id, target: 'owner'|'maid', title, body }
import { AppError, handle, requireCronSecret, requireFields } from "../_shared/http.ts";
import { db, must } from "../_shared/db.ts";
import { activeCook } from "../_shared/auth.ts";
import { sendPush } from "../_shared/fcm.ts";

handle(async (body, req) => {
  requireCronSecret(req);
  requireFields(body, "house_id", "target", "title", "body");
  const sb = db("system");
  const house = must(await sb.from("house").select("owner_fcm_token").eq("id", body.house_id).maybeSingle()) as
    | { owner_fcm_token: string | null }
    | null;
  if (!house) throw new AppError("NOT_FOUND", "House not found");
  const token = body.target === "owner"
    ? house.owner_fcm_token
    : (await activeCook(sb, body.house_id))?.fcm_token;
  const sent = await sendPush(token, String(body.title), String(body.body), { kind: "manual" });
  return { sent };
});
