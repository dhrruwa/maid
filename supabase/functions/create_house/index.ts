// Owner first-launch setup. Idempotent: calling again from the same phone
// returns the existing house.
import { handle, randomHex, requireFields, sha256Hex, AppError } from "../_shared/http.ts";
import { db, must } from "../_shared/db.ts";
import { House, publicHouse } from "../_shared/auth.ts";

handle(async (body) => {
  requireFields(body, "device_id", "pin_hash", "lat", "lng");
  if (typeof body.device_id !== "string" || body.device_id.length < 16) {
    throw new AppError("NO_DEVICE", "device_id must be at least 16 characters", {}, 400);
  }
  const sb = db("owner");

  const existing = must(
    await sb.from("house").select("*").eq("owner_device_id", body.device_id).maybeSingle(),
  ) as House | null;
  if (existing) {
    const settings = must(await sb.from("settings").select("*").eq("house_id", existing.id).single());
    return { house: publicHouse(existing), settings, recovery_key: null };
  }

  const lat = Number(body.lat), lng = Number(body.lng);
  if (!isFinite(lat) || !isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    throw new AppError("BAD_LOCATION", "Invalid location");
  }

  // Shown once to the owner; lets them move to a new phone later.
  const recoveryKey = randomHex(6).toUpperCase().match(/.{4}/g)!.join("-");

  const house = must(
    await sb.from("house").insert({
      name: String(body.name ?? "Home").slice(0, 60) || "Home",
      lat,
      lng,
      radius_m: Math.max(20, Math.min(2000, Number(body.radius_m ?? 100) || 100)),
      owner_pin_hash: String(body.pin_hash),
      owner_device_id: body.device_id,
      owner_fcm_token: body.fcm_token ?? null,
      recovery_key_hash: await sha256Hex(recoveryKey),
    }).select("*").single(),
  ) as House;

  const settings = must(
    await sb.from("settings").insert({ house_id: house.id }).select("*").single(),
  );

  return { house: publicHouse(house), settings, recovery_key: recoveryKey };
});
