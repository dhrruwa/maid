// Owner: set the dishes for one date + slot. Replaces what was there.
// body: { device_id, date, slot, items: [{ dish_id? , name?, youtube_url?, notes? }] }
// Items without dish_id are saved into "My dishes" first (reusing a dish with
// the same name).
import { AppError, handle, requireFields } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { ownerCtx } from "../_shared/auth.ts";
import { cleanYoutube, notifyMenuChange, offSlots } from "../_shared/menu.ts";
import { menuFor, Slot } from "../_shared/pay.ts";
import { isValidDate } from "../_shared/time.ts";

handle(async (body) => {
  requireFields(body, "date", "slot");
  const ctx = await ownerCtx(body);
  const { sb, house } = ctx;
  const date = body.date as string;
  const slot = body.slot as Slot;
  if (!isValidDate(date)) throw new AppError("BAD_DATE", "Invalid date");
  if (slot !== "morning" && slot !== "evening") throw new AppError("BAD_SLOT", "Invalid slot");
  const items = Array.isArray(body.items) ? body.items : [];
  if (items.length > 12) throw new AppError("TOO_MANY", "At most 12 dishes per meal");

  if (items.length) {
    const off = (await offSlots(sb, house.id, date))[slot];
    if (off) {
      throw new AppError("SLOT_OFF", `No cooking needed: ${off.type.replace("_", " ")}`, { type: off.type });
    }
  }

  // Resolve every item to a dish id.
  const wanted: { dish_id: string; notes: string | null }[] = [];
  for (const it of items) {
    let dishId = it.dish_id as string | undefined;
    if (!dishId) {
      const name = String(it.name ?? "").trim().slice(0, 80);
      if (!name) throw new AppError("MISSING_FIELD", "Dish name is required");
      const yt = cleanYoutube(it.youtube_url);
      const found = must(
        await sb.from("dishes").select("id,youtube_url").eq("house_id", house.id).is("deleted_at", null)
          .ilike("name", name.replace(/[%_]/g, "\\$&")).limit(1).maybeSingle(),
      ) as { id: string; youtube_url: string | null } | null;
      if (found) {
        dishId = found.id;
        if (yt && yt !== found.youtube_url) {
          must(await sb.from("dishes").update({ youtube_url: yt }).eq("id", found.id));
        }
      } else {
        dishId = must(
          await sb.from("dishes").insert({ house_id: house.id, name, youtube_url: yt }).select("id").single(),
        ).id as string;
      }
    } else {
      const ok = must(
        await sb.from("dishes").select("id").eq("id", dishId).eq("house_id", house.id).maybeSingle(),
      );
      if (!ok) throw new AppError("NOT_FOUND", "Dish not found");
    }
    wanted.push({ dish_id: dishId!, notes: it.notes ? String(it.notes).slice(0, 300) : null });
  }

  const current = must(
    await sb.from("menu").select("id,dish_id,notes,sort_order").eq("house_id", house.id)
      .eq("date", date).eq("slot", slot).is("deleted_at", null).order("sort_order"),
  ) as { id: string; dish_id: string; notes: string | null; sort_order: number }[];

  let changed = false;
  const keep = new Set<string>();
  for (let i = 0; i < wanted.length; i++) {
    const w = wanted[i];
    const match = current.find((c) => c.dish_id === w.dish_id && !keep.has(c.id));
    if (match) {
      keep.add(match.id);
      if (match.notes !== w.notes || match.sort_order !== i) {
        must(await sb.from("menu").update({ notes: w.notes, sort_order: i }).eq("id", match.id));
        changed = true;
      }
    } else {
      must(await sb.from("menu").insert({
        house_id: house.id,
        date,
        slot,
        dish_id: w.dish_id,
        notes: w.notes,
        sort_order: i,
      }));
      changed = true;
    }
  }
  const remove = current.filter((c) => !keep.has(c.id)).map((c) => c.id);
  if (remove.length) {
    must(await sb.from("menu").update({ deleted_at: new Date().toISOString() }).in("id", remove));
    changed = true;
  }

  if (changed) await notifyMenuChange(ctx, [{ date, slot }]);

  const menus = await menuFor(sb, house.id, date, date);
  return { date, slot, items: menus.get(date)?.[slot] ?? [], changed };
});
