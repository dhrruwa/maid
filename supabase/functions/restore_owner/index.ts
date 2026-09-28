// Move the owner role to a new phone using the recovery key shown at setup.
import { AppError, handle, requireFields, sha256Hex } from "../_shared/http.ts";
import { db, must } from "../_shared/db.ts";
import { House, publicHouse } from "../_shared/auth.ts";

handle(async (body) => {
  requireFields(body, "device_id", "recovery_key");
  if (String(body.device_id).length < 16) throw new AppError("NO_DEVICE", "Bad device_id", {}, 400);
  const key = String(body.recovery_key).trim().toUpperCase().replace(/[^0-9A-F]/g, "")
    .match(/.{1,4}/g)?.join("-") ?? "";
  const sb = db("owner");
  const house = must(
    await sb.from("house").select("*").eq("recovery_key_hash", await sha256Hex(key)).maybeSingle(),
  ) as House | null;
  if (!house) {
    // Slow down guessing.
    await new Promise((r) => setTimeout(r, 1500));
    throw new AppError("BAD_RECOVERY_KEY", "Recovery key not recognised");
  }
  const updated = must(
    await sb.from("house").update({
      owner_device_id: body.device_id,
      owner_fcm_token: body.fcm_token ?? house.owner_fcm_token,
    }).eq("id", house.id).select("*").single(),
  ) as House;
  const settings = must(await sb.from("settings").select("*").eq("house_id", house.id).single());
  return { house: publicHouse(updated), settings };
});
