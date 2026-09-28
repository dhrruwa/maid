// Owner: new house QR token. The old printed QR stops working immediately.
import { handle, randomHex } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { ownerCtx, publicHouse } from "../_shared/auth.ts";

handle(async (body) => {
  const ctx = await ownerCtx(body);
  const house = must(
    await ctx.sb.from("house").update({ qr_token: randomHex(24) }).eq("id", ctx.house.id)
      .select("*").single(),
  );
  return { house: publicHouse(house) };
});
