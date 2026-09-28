// Owner: add or edit a dish in "My dishes".
// body: { device_id, id?, name, youtube_url?, notes? }
import { AppError, handle, requireFields } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { ownerCtx } from "../_shared/auth.ts";
import { cleanYoutube } from "../_shared/menu.ts";

handle(async (body) => {
  requireFields(body, "name");
  const ctx = await ownerCtx(body);
  const row = {
    name: String(body.name).trim().slice(0, 80),
    youtube_url: cleanYoutube(body.youtube_url),
    notes: body.notes ? String(body.notes).slice(0, 300) : null,
  };
  if (!row.name) throw new AppError("MISSING_FIELD", "Dish name is required");

  if (body.id) {
    const dish = must(
      await ctx.sb.from("dishes").update(row).eq("id", body.id).eq("house_id", ctx.house.id)
        .select("*").maybeSingle(),
    );
    if (!dish) throw new AppError("NOT_FOUND", "Dish not found");
    return { dish };
  }
  const dish = must(
    await ctx.sb.from("dishes").insert({ ...row, house_id: ctx.house.id }).select("*").single(),
  );
  return { dish };
});
