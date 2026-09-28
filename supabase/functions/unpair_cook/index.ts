// Owner: unlink the maid phone. Her history stays; she must pair again to scan.
import { handle } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { ownerCtx } from "../_shared/auth.ts";

handle(async (body) => {
  const ctx = await ownerCtx(body);
  must(
    await ctx.sb.from("cook_device").update({ active: false })
      .eq("house_id", ctx.house.id).eq("active", true),
  );
  return { unpaired: true };
});
