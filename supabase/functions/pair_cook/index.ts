// Maid phone: link to the house using the pairing QR token or the 6-digit code.
// body: { pairing_token? | code?, device_id, name, fcm_token?, lang? }
import { AppError, handle, requireFields } from "../_shared/http.ts";
import { db, must } from "../_shared/db.ts";
import { activeCook, House, Settings } from "../_shared/auth.ts";
import { sendPush } from "../_shared/fcm.ts";

handle(async (body) => {
  requireFields(body, "device_id", "name");
  if (String(body.device_id).length < 16) throw new AppError("NO_DEVICE", "Bad device_id", {}, 400);
  const sb = db("maid");
  const nowIso = new Date().toISOString();

  let q = sb.from("pairing_tokens").select("*").eq("used", false).gt("expires_at", nowIso);
  if (body.pairing_token) {
    q = q.eq("token", String(body.pairing_token).replace(/^CDPAIR:/, ""));
  } else if (body.code) {
    q = q.eq("code_6digit", String(body.code).replace(/\D/g, ""));
  } else {
    throw new AppError("MISSING_FIELD", "pairing_token or code is required", {}, 400);
  }
  const tok = must(await q.limit(1).maybeSingle()) as
    | { token: string; house_id: string }
    | null;
  if (!tok) {
    await new Promise((r) => setTimeout(r, 1000)); // slow down code guessing
    throw new AppError("PAIRING_INVALID", "This code is wrong or expired. Ask the owner for a new one.");
  }

  must(await sb.from("pairing_tokens").update({ used: true }).eq("token", tok.token));

  // Only one maid phone per house: deactivate the previous one.
  const prev = await activeCook(sb, tok.house_id);
  if (prev) must(await sb.from("cook_device").update({ active: false }).eq("house_id", tok.house_id).eq("active", true));

  const cook = must(
    await sb.from("cook_device").insert({
      house_id: tok.house_id,
      device_id: body.device_id,
      name: String(body.name).slice(0, 40),
      fcm_token: body.fcm_token ?? null,
      lang: body.lang === "kn" ? "kn" : "en",
    }).select("*").single(),
  );
  const house = must(await sb.from("house").select("*").eq("id", tok.house_id).single()) as House;
  const settings = must(await sb.from("settings").select("*").eq("house_id", tok.house_id).single()) as Settings;

  await sendPush(house.owner_fcm_token, "Maid phone paired", `${cook.name}'s phone is now linked.`, {
    kind: "pair",
  });

  return {
    house_name: house.name,
    name: cook.name,
    rates: {
      weekday_rate: settings.weekday_rate,
      weekend_rate: settings.weekend_rate,
      morning_start: settings.morning_start,
      morning_end: settings.morning_end,
      evening_start: settings.evening_start,
      evening_end: settings.evening_end,
    },
  };
});
