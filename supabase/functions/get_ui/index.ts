// Maid phone: the server-driven UI bundle (which blocks each screen shows,
// plus text overrides). See docs/SDUI.md.
// body: { device_id, schema }   schema = newest block schema the app knows
// → { ui: { id, schema, screens, strings } | null }   null = keep the built-in layout
import { handle } from "../_shared/http.ts";
import { maidCtx } from "../_shared/auth.ts";
import { must } from "../_shared/db.ts";

handle(async (body) => {
  const ctx = await maidCtx(body);
  const schema = Number.isInteger(body.schema) && body.schema > 0 ? body.schema : 1;
  // This house's newest bundle first (nulls last), then the newest global one.
  const row = must(
    await ctx.sb.from("app_ui").select("id, schema, screens, strings")
      .eq("app", "maid").eq("active", true).lte("schema", schema)
      .or(`house_id.is.null,house_id.eq.${ctx.house.id}`)
      .order("house_id", { ascending: true, nullsFirst: false })
      .order("created_at", { ascending: false })
      .limit(1).maybeSingle(),
  );
  return { ui: row ?? null };
});
