// Owner: house, settings and paired maid phone.
import { handle } from "../_shared/http.ts";
import { ownerCtx, publicCook, publicHouse } from "../_shared/auth.ts";

handle(async (body) => {
  const ctx = await ownerCtx(body);
  return { house: publicHouse(ctx.house), settings: ctx.settings, cook: publicCook(ctx.cook) };
});
