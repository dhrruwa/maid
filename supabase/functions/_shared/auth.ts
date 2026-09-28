import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { Actor, db, must } from "./db.ts";
import { AppError, Body } from "./http.ts";

export interface House {
  id: string;
  name: string;
  lat: number | null;
  lng: number | null;
  radius_m: number;
  qr_token: string;
  owner_pin_hash: string | null;
  owner_device_id: string;
  owner_fcm_token: string | null;
  created_at: string;
}

export interface Settings {
  house_id: string;
  weekday_rate: number;
  weekend_rate: number;
  morning_start: string;
  morning_end: string;
  evening_start: string;
  evening_end: string;
  notify_scan: boolean;
  notify_leave: boolean;
  notify_offline: boolean;
  notify_payday: boolean;
  notify_menu: boolean;
}

export interface CookDevice {
  id: string;
  house_id: string;
  device_id: string;
  name: string;
  fcm_token: string | null;
  lang: "en" | "kn";
  paired_at: string;
  active: boolean;
}

export interface Ctx {
  role: "owner" | "maid";
  sb: SupabaseClient;
  house: House;
  settings: Settings;
  cook: CookDevice | null; // the active maid phone (for the owner too, if paired)
}

function deviceId(body: Body): string {
  const id = body.device_id;
  if (typeof id !== "string" || id.length < 16) {
    throw new AppError("NO_DEVICE", "device_id is required", {}, 401);
  }
  return id;
}

async function loadSettings(sb: SupabaseClient, houseId: string): Promise<Settings> {
  return must(await sb.from("settings").select("*").eq("house_id", houseId).single()) as Settings;
}

export async function activeCook(sb: SupabaseClient, houseId: string): Promise<CookDevice | null> {
  return must(
    await sb.from("cook_device").select("*").eq("house_id", houseId).eq("active", true)
      .order("paired_at", { ascending: false }).limit(1).maybeSingle(),
  ) as CookDevice | null;
}

export async function ownerCtx(body: Body): Promise<Ctx> {
  const id = deviceId(body);
  const sb = db("owner");
  const house = must(
    await sb.from("house").select("*").eq("owner_device_id", id).maybeSingle(),
  ) as House | null;
  if (!house) throw new AppError("NOT_OWNER", "This phone is not the owner phone", {}, 401);
  return { role: "owner", sb, house, settings: await loadSettings(sb, house.id), cook: await activeCook(sb, house.id) };
}

export async function maidCtx(body: Body): Promise<Ctx> {
  const id = deviceId(body);
  const sb = db("maid");
  const cook = must(
    await sb.from("cook_device").select("*").eq("device_id", id).eq("active", true)
      .order("paired_at", { ascending: false }).limit(1).maybeSingle(),
  ) as CookDevice | null;
  if (!cook) throw new AppError("NOT_PAIRED", "This phone is not paired", {}, 401);
  const house = must(await sb.from("house").select("*").eq("id", cook.house_id).single()) as House;
  return { role: "maid", sb, house, settings: await loadSettings(sb, house.id), cook };
}

/** Either the owner phone or the paired maid phone. */
export async function anyCtx(body: Body): Promise<Ctx> {
  try {
    return await ownerCtx(body);
  } catch (e) {
    if (e instanceof AppError && e.code === "NOT_OWNER") return await maidCtx(body);
    throw e;
  }
}

export function actorOf(ctx: Ctx): Actor {
  return ctx.role;
}

/** House fields safe to send to the owner app (no PIN hash / recovery hash). */
export function publicHouse(h: House, withQr = true) {
  return {
    id: h.id,
    name: h.name,
    lat: h.lat,
    lng: h.lng,
    radius_m: h.radius_m,
    qr_token: withQr ? h.qr_token : undefined,
    owner_pin_hash: h.owner_pin_hash,
    created_at: h.created_at,
  };
}

export function publicCook(c: CookDevice | null) {
  return c ? { id: c.id, name: c.name, paired_at: c.paired_at, lang: c.lang } : null;
}
