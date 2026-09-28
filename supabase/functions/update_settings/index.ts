// Owner: change house details, PIN, pay rates, time windows, notifications.
// body: { device_id, house?: {name, lat, lng, radius_m, owner_pin_hash}, settings?: {...} }
import { AppError, handle } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { ownerCtx, publicCook, publicHouse } from "../_shared/auth.ts";
import { timeToMin } from "../_shared/time.ts";

const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d(:00)?$/;

handle(async (body) => {
  const ctx = await ownerCtx(body);
  const { sb, house } = ctx;

  const h = body.house ?? {};
  const housePatch: Record<string, unknown> = {};
  if (h.name !== undefined) housePatch.name = String(h.name).slice(0, 60) || "Home";
  if (h.radius_m !== undefined) {
    const r = Number(h.radius_m);
    if (!isFinite(r) || r < 20 || r > 2000) throw new AppError("BAD_RADIUS", "Radius must be 20–2000 m");
    housePatch.radius_m = Math.round(r);
  }
  if (h.lat !== undefined || h.lng !== undefined) {
    const lat = Number(h.lat), lng = Number(h.lng);
    if (!isFinite(lat) || !isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
      throw new AppError("BAD_LOCATION", "Invalid location");
    }
    housePatch.lat = lat;
    housePatch.lng = lng;
  }
  if (h.owner_pin_hash !== undefined) housePatch.owner_pin_hash = String(h.owner_pin_hash);

  const s = body.settings ?? {};
  const settingsPatch: Record<string, unknown> = {};
  for (const k of ["weekday_rate", "weekend_rate"]) {
    if (s[k] !== undefined) {
      const v = Number(s[k]);
      if (!Number.isInteger(v) || v < 0 || v > 100000) throw new AppError("BAD_RATE", "Rate must be a whole number");
      settingsPatch[k] = v;
    }
  }
  for (const k of ["morning_start", "morning_end", "evening_start", "evening_end"]) {
    if (s[k] !== undefined) {
      if (!TIME_RE.test(String(s[k]))) throw new AppError("BAD_TIME", `Invalid time for ${k}`);
      settingsPatch[k] = String(s[k]).slice(0, 5);
    }
  }
  for (const k of ["notify_scan", "notify_leave", "notify_offline", "notify_payday", "notify_menu"]) {
    if (s[k] !== undefined) settingsPatch[k] = Boolean(s[k]);
  }

  const merged = { ...ctx.settings, ...settingsPatch } as unknown as Record<string, string>;
  const ms = timeToMin(merged.morning_start), me = timeToMin(merged.morning_end);
  const es = timeToMin(merged.evening_start), ee = timeToMin(merged.evening_end);
  if (!(ms < me && me <= es && es < ee)) {
    throw new AppError("BAD_WINDOWS", "Morning must end before evening starts, and each start before its end");
  }

  let newHouse = house;
  if (Object.keys(housePatch).length) {
    newHouse = must(await sb.from("house").update(housePatch).eq("id", house.id).select("*").single());
  }
  let newSettings = ctx.settings;
  if (Object.keys(settingsPatch).length) {
    newSettings = must(
      await sb.from("settings").update(settingsPatch).eq("house_id", house.id).select("*").single(),
    );
  }
  return { house: publicHouse(newHouse), settings: newSettings, cook: publicCook(ctx.cook) };
});
