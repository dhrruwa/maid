import { Ctx } from "./auth.ts";
import { sendPush } from "./fcm.ts";

export type OwnerKind = "scan" | "leave" | "offline" | "payday";

/** Push to the owner, respecting their on/off setting for this kind. */
export async function notifyOwner(
  ctx: Ctx,
  kind: OwnerKind,
  title: string,
  body: string,
  data: Record<string, string> = {},
) {
  const pref = {
    scan: ctx.settings.notify_scan,
    leave: ctx.settings.notify_leave,
    offline: ctx.settings.notify_offline,
    payday: ctx.settings.notify_payday,
  }[kind];
  if (!pref) return false;
  return await sendPush(ctx.house.owner_fcm_token, title, body, { kind, ...data });
}

/** A maid message in English and Kannada; the one matching her app language is sent. */
export interface Bilingual {
  en: { title: string; body: string };
  kn: { title: string; body: string };
}

export async function notifyMaid(ctx: Ctx, msg: Bilingual, data: Record<string, string> = {}) {
  const cook = ctx.cook;
  if (!cook?.fcm_token) return false;
  const lang = cook.lang === "kn" ? "kn" : "en";
  const m = msg[lang];
  return await sendPush(cook.fcm_token, m.title, m.body, data);
}

export const KN = {
  morning: "ಬೆಳಿಗ್ಗೆ",
  evening: "ಸಂಜೆ",
  full: "ಇಡೀ ದಿನ",
  today: "ಇಂದು",
  tomorrow: "ನಾಳೆ",
};

export const slotEn = (s: string) =>
  s === "morning" ? "Morning" : s === "evening" ? "Evening" : "Full day";
export const slotKn = (s: string) =>
  s === "morning" ? KN.morning : s === "evening" ? KN.evening : KN.full;
