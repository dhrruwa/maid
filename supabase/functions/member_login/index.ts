// Family app: log in once with name + 4-digit PIN; the phone stays logged in.
// body: { device_id, name, pin, fcm_token? }
// → { member: { id, name }, house_name }
// Errors: LOGIN_FAILED (wrong name or PIN, same error for both, after ~1 s),
//         LOGIN_LOCKED { until } (5 wrong PINs → locked for 15 minutes).
import { AppError, handle, requireFields } from "../_shared/http.ts";
import { db, must } from "../_shared/db.ts";
import {
  cleanName,
  isPin,
  likeSafe,
  LOCK_MINUTES,
  MAX_FAILED_LOGINS,
  nameKey,
  pinHash,
  pinOf,
} from "../_shared/family.ts";

interface Candidate {
  id: string;
  name: string;
  pin_hash: string;
  failed_attempts: number;
  locked_until: string | null;
  house: { name: string } | { name: string }[] | null;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Constant-time comparison of two hex strings. */
function sameHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

const failed = () => new AppError("LOGIN_FAILED", "The name or PIN is wrong");
const locked = (until: string) =>
  new AppError("LOGIN_LOCKED", `Too many wrong PINs. Try again in ${LOCK_MINUTES} minutes.`, { until });

handle(async (body) => {
  // Every failure answers at the same moment (~1 s after the request came in),
  // so a wrong name cannot be told from a wrong PIN by timing.
  const deadline = Date.now() + 1000;
  const fail = async (e: AppError): Promise<never> => {
    await sleep(Math.max(0, deadline - Date.now()));
    throw e;
  };

  requireFields(body, "device_id", "name", "pin");
  const deviceId = String(body.device_id);
  if (deviceId.length < 16) throw new AppError("NO_DEVICE", "Bad device_id", {}, 400);
  const sb = db("member");
  const name = cleanName(body.name);
  const pin = pinOf(body.pin);

  if (!likeSafe(name) || !isPin(pin)) return fail(failed());

  // ILIKE without wildcards = case-insensitive equality; then exact key match.
  const rows = must(
    await sb.from("members")
      .select("id,name,pin_hash,failed_attempts,locked_until,house(name)")
      .eq("active", true).ilike("name", name),
  ) as Candidate[];
  const candidates = rows.filter((r) => nameKey(r.name) === nameKey(name));
  if (!candidates.length) return fail(failed());

  const nowMs = Date.now();
  const lockedUntil = (c: Candidate) =>
    c.locked_until && Date.parse(c.locked_until) > nowMs ? Date.parse(c.locked_until) : 0;
  const open = candidates.filter((c) => !lockedUntil(c));
  if (!open.length) {
    return fail(locked(new Date(Math.min(...candidates.map(lockedUntil))).toISOString()));
  }

  let lockIso: string | null = null;
  for (const c of open) {
    // Each PIN check first claims one attempt with a compare-and-set on
    // failed_attempts (and the lock state that was read). Parallel requests
    // that read the same state lose the race and are refused without a check,
    // so a burst of guesses cannot get past the 5-try lockout.
    const attempts = c.failed_attempts + 1;
    let claim = sb.from("members").update({ failed_attempts: attempts })
      .eq("id", c.id).eq("active", true).eq("failed_attempts", c.failed_attempts);
    claim = c.locked_until === null
      ? claim.is("locked_until", null)
      : claim.lte("locked_until", new Date(nowMs).toISOString());
    const claimed = must(await claim.select("id")) as { id: string }[];
    if (!claimed.length) continue;

    if (sameHex(await pinHash(c.id, pin), c.pin_hash)) {
      // A phone is one member at a time: log this phone out of anyone else first.
      must(
        await sb.from("members").update({ device_id: null, fcm_token: null, linked_at: null })
          .eq("device_id", deviceId).neq("id", c.id),
      );
      const m = must(
        await sb.from("members").update({
          failed_attempts: 0,
          locked_until: null,
          device_id: deviceId,
          fcm_token: typeof body.fcm_token === "string" && body.fcm_token ? body.fcm_token : null,
          linked_at: new Date().toISOString(),
        }).eq("id", c.id).select("id,name").single(),
      ) as { id: string; name: string };
      const house = Array.isArray(c.house) ? c.house[0] : c.house;
      return { member: { id: m.id, name: m.name }, house_name: house?.name ?? "" };
    }

    // Wrong PIN (already counted by the claim); the 5th miss locks.
    if (attempts >= MAX_FAILED_LOGINS) {
      lockIso = new Date(nowMs + LOCK_MINUTES * 60000).toISOString();
      must(await sb.from("members").update({ locked_until: lockIso }).eq("id", c.id));
    }
  }
  return fail(lockIso ? locked(lockIso) : failed());
});
