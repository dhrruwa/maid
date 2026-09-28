// Owner: one-time pairing token (QR) + 6-digit backup code, valid 10 minutes.
import { handle, randomHex } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { ownerCtx } from "../_shared/auth.ts";

handle(async (body) => {
  const ctx = await ownerCtx(body);
  const { sb, house } = ctx;

  // Only the newest code works.
  must(await sb.from("pairing_tokens").update({ used: true }).eq("house_id", house.id).eq("used", false));

  const nowIso = new Date().toISOString();
  let code = "";
  for (let i = 0; i < 10; i++) {
    const n = new Uint32Array(1);
    crypto.getRandomValues(n);
    code = String(n[0] % 1000000).padStart(6, "0");
    const clash = must(
      await sb.from("pairing_tokens").select("token").eq("code_6digit", code).eq("used", false)
        .gt("expires_at", nowIso).limit(1),
    ) as unknown[];
    if (!clash.length) break;
  }

  const token = randomHex(20);
  const expires = new Date(Date.now() + 10 * 60 * 1000).toISOString();
  must(await sb.from("pairing_tokens").insert({
    token,
    code_6digit: code,
    house_id: house.id,
    expires_at: expires,
  }));
  return { token, code, expires_at: expires, qr_payload: `CDPAIR:${token}` };
});
