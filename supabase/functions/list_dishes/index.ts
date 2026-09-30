// Owner: "My dishes", with how often each was put on the menu.
import { handle } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { ownerCtx } from "../_shared/auth.ts";

handle(async (body) => {
  const ctx = await ownerCtx(body);
  const [dishes, uses] = await Promise.all([
    ctx.sb.from("dishes").select("id,name,name_kn,youtube_url,notes,notes_kn,created_at").eq("house_id", ctx.house.id)
      .is("deleted_at", null).order("name"),
    ctx.sb.from("menu").select("dish_id").eq("house_id", ctx.house.id).is("deleted_at", null),
  ]);
  const counts = new Map<string, number>();
  for (const u of must(uses) as { dish_id: string }[]) counts.set(u.dish_id, (counts.get(u.dish_id) ?? 0) + 1);
  return {
    dishes: (must(dishes) as { id: string }[]).map((d) => ({ ...d, times_used: counts.get(d.id) ?? 0 })),
  };
});
