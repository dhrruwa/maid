// Either phone: live salary card for the current cycle (1st → today).
import { handle } from "../_shared/http.ts";
import { anyCtx } from "../_shared/auth.ts";
import { liveSalary } from "../_shared/pay.ts";

handle(async (body) => {
  const ctx = await anyCtx(body);
  return { salary: await liveSalary(ctx), house_name: ctx.house.name, maid_name: ctx.cook?.name ?? null };
});
