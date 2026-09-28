// Maid phone: record a visit after scanning the house QR.
// body: { device_id, qr_token, lat, lng, is_mocked, scanned_at?, is_offline }
//
// Online scans use server time. Offline scans use the saved scanned_at and are
// accepted only if uploaded within 12 hours and the saved time is in a slot.
import { AppError, handle, haversineM, requireFields } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { maidCtx, Settings } from "../_shared/auth.ts";
import { liveSalary, Slot, slotRate } from "../_shared/pay.ts";
import { IstNow, minToLabel, timeToMin, toIst } from "../_shared/time.ts";
import { notifyOwner } from "../_shared/notify.ts";

const OFFLINE_MAX_MS = 12 * 60 * 60 * 1000;
const CLOCK_SKEW_MS = 5 * 60 * 1000;

function pickSlot(s: Settings, t: IstNow): Slot {
  const ms = timeToMin(s.morning_start), me = timeToMin(s.morning_end);
  const es = timeToMin(s.evening_start), ee = timeToMin(s.evening_end);
  const weekend = t.dow === 0 || t.dow === 6;
  const windows = {
    morning: `${minToLabel(ms)} – ${minToLabel(me)}`,
    evening: `${minToLabel(es)} – ${minToLabel(ee)}`,
  };

  if (t.minutes >= ms && t.minutes < me) return "morning";
  if (t.minutes >= es && t.minutes < ee) {
    if (weekend) {
      throw new AppError("EVENING_NOT_NEEDED", "Evening not needed on Saturday and Sunday", {
        day: t.dow === 0 ? "Sunday" : "Saturday",
      });
    }
    return "evening";
  }
  if (t.minutes < ms) {
    throw new AppError("TOO_EARLY", `Too early. Morning starts at ${minToLabel(ms)}`, {
      opens: minToLabel(ms),
      window: windows.morning,
    });
  }
  if (t.minutes >= me && t.minutes < es) {
    throw new AppError("MORNING_OVER", `Time is over for morning (${windows.morning})`, {
      window: windows.morning,
      evening_opens: weekend ? null : minToLabel(es),
    });
  }
  // after evening end
  if (weekend) {
    throw new AppError("MORNING_OVER", `Time is over for morning (${windows.morning})`, {
      window: windows.morning,
      evening_opens: null,
    });
  }
  throw new AppError("EVENING_OVER", `Time is over for evening (${windows.evening})`, {
    window: windows.evening,
  });
}

handle(async (body) => {
  requireFields(body, "device_id", "qr_token", "lat", "lng");
  const ctx = await maidCtx(body);
  const { sb, house, settings } = ctx;

  const qr = String(body.qr_token).replace(/^CDHOUSE:/, "");
  if (qr !== house.qr_token) throw new AppError("WRONG_QR", "This is not the house QR code");

  if (body.is_mocked === true) {
    throw new AppError("MOCK_LOCATION", "Fake location detected. Turn off mock location apps.");
  }

  if (house.lat == null || house.lng == null) {
    throw new AppError("HOUSE_LOCATION_NOT_SET", "The owner has not set the house location");
  }
  const lat = Number(body.lat), lng = Number(body.lng);
  if (!isFinite(lat) || !isFinite(lng)) throw new AppError("BAD_LOCATION", "Location not available");
  const distance = Math.round(haversineM(lat, lng, house.lat, house.lng));
  if (distance > house.radius_m) {
    throw new AppError("NOT_AT_HOUSE", "You are not at the house", {
      distance_m: distance,
      radius_m: house.radius_m,
    });
  }

  const now = new Date();
  const isOffline = body.is_offline === true;
  let scannedAt = now;
  if (isOffline) {
    scannedAt = new Date(String(body.scanned_at ?? ""));
    if (isNaN(scannedAt.getTime())) throw new AppError("BAD_TIME", "Saved scan time is missing");
    if (scannedAt.getTime() > now.getTime() + CLOCK_SKEW_MS) {
      throw new AppError("BAD_TIME", "Phone clock is wrong. Please fix the date and time.");
    }
    if (now.getTime() - scannedAt.getTime() > OFFLINE_MAX_MS) {
      throw new AppError("OFFLINE_TOO_OLD", "This saved scan is older than 12 hours and cannot be accepted");
    }
  }

  const t = toIst(scannedAt);
  const slot = pickSlot(settings, t);

  const existing = must(
    await sb.from("attendance").select("id").eq("house_id", house.id).eq("date", t.date)
      .eq("slot", slot).is("deleted_at", null).maybeSingle(),
  );
  if (existing) {
    throw new AppError("ALREADY_MARKED", `${slot === "morning" ? "Morning" : "Evening"} already marked`, { slot });
  }

  const amount = slotRate(settings, t.date, slot);
  const ins = await sb.from("attendance").insert({
    house_id: house.id,
    device_id: body.device_id,
    date: t.date,
    slot,
    scanned_at: scannedAt.toISOString(),
    uploaded_at: now.toISOString(),
    lat,
    lng,
    distance_m: distance,
    amount,
    is_offline: isOffline,
  }).select("*").single();
  if (ins.error?.code === "23505") {
    throw new AppError("ALREADY_MARKED", `${slot === "morning" ? "Morning" : "Evening"} already marked`, { slot });
  }
  const row = must(ins);

  const slotName = slot === "morning" ? "Morning" : "Evening";
  const timeLabel = minToLabel(t.minutes);
  if (isOffline) {
    await notifyOwner(
      ctx,
      "offline",
      "Offline scan uploaded",
      `${ctx.cook!.name}: ${slotName} at ${timeLabel} (uploaded ${minToLabel(toIst(now).minutes)}) · ₹${amount}`,
      { date: t.date },
    );
  } else {
    await notifyOwner(
      ctx,
      "scan",
      `${slotName} attendance marked`,
      `${slotName} attendance marked at ${timeLabel} · ₹${amount}`,
      { date: t.date },
    );
  }

  const salary = await liveSalary(ctx);
  return {
    attendance: {
      id: row.id,
      date: t.date,
      slot,
      scanned_at: row.scanned_at,
      time_label: timeLabel,
      amount,
      distance_m: distance,
      is_offline: isOffline,
    },
    earned_so_far: salary.earned,
    salary,
  };
});
