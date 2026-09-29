// Owner: what was cooked between two dates + "Most cooked dishes".
// body: { device_id, from, to }
import { AppError, handle, requireFields } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { ownerCtx } from "../_shared/auth.ts";
import { menuFor } from "../_shared/pay.ts";
import { daysBetween, isValidDate } from "../_shared/time.ts";

handle(async (body) => {
  requireFields(body, "from", "to");
  const ctx = await ownerCtx(body);
  const { from, to } = body;
  if (!isValidDate(from) || !isValidDate(to) || to < from) throw new AppError("BAD_DATE", "Invalid dates");
  if (daysBetween(from, to) > 366) throw new AppError("RANGE_TOO_LONG", "At most one year at a time");

  // The range and the all-time top dishes load in parallel.
  const [menus, allRes] = await Promise.all([
    menuFor(ctx.sb, ctx.house.id, from, to),
    ctx.sb.from("menu").select("dish_id,dishes(name)").eq("house_id", ctx.house.id)
      .is("deleted_at", null),
  ]);
  const days = [...menus.entries()]
    .sort(([a], [b]) => (a < b ? 1 : -1))
    .map(([date, m]) => ({ date, ...m }));

  // All-time top dishes
  const all = must(allRes) as { dish_id: string; dishes: { name: string } | null }[];
  const counts = new Map<string, { dish_id: string; name: string; count: number }>();
  for (const r of all) {
    const c = counts.get(r.dish_id) ?? { dish_id: r.dish_id, name: r.dishes?.name ?? "?", count: 0 };
    c.count++;
    counts.set(r.dish_id, c);
  }
  const top = [...counts.values()].sort((a, b) => b.count - a.count).slice(0, 15);

  return { days, top_dishes: top };
});
