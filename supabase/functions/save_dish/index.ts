// Owner: add or edit a dish in "My dishes".
// body: { device_id, id?, name, youtube_url?, notes?, name_kn?, notes_kn? }
// name_kn / notes_kn: sent only when the owner typed or corrected the Kannada
// ("" = go back to the automatic translation). Otherwise it is translated.
import { AppError, handle, requireFields } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { ownerCtx } from "../_shared/auth.ts";
import { cleanYoutube } from "../_shared/menu.ts";
import { rememberKannada, toKannada } from "../_shared/translate.ts";

handle(async (body) => {
  requireFields(body, "name");
  const ctx = await ownerCtx(body);
  const name = String(body.name).trim().slice(0, 80);
  const notes = body.notes ? String(body.notes).slice(0, 300) : null;
  if (!name) throw new AppError("MISSING_FIELD", "Dish name is required");
  const youtube_url = cleanYoutube(body.youtube_url);

  if (typeof body.name_kn === "string") await rememberKannada(ctx.sb, name, body.name_kn);
  if (typeof body.notes_kn === "string" && notes) await rememberKannada(ctx.sb, notes, body.notes_kn);
  const [name_kn, notes_kn] = await toKannada(ctx.sb, [name, notes]);
  const row = { name, name_kn, youtube_url, notes, notes_kn };

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
