// Owner: copy one day's menu to other days, or repeat it weekly.
// body: { device_id, from_date, to_dates?: [date], repeat_weeks?: 1..12, slots?: ['morning','evening'] }
// Target slots that are holidays / approved leave / weekend evenings are skipped.
import { AppError, handle, requireFields } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { ownerCtx } from "../_shared/auth.ts";
import { notifyMenuChange, offSlots } from "../_shared/menu.ts";
import { menuFor, Slot } from "../_shared/pay.ts";
import { addDays, isValidDate } from "../_shared/time.ts";

handle(async (body) => {
  requireFields(body, "from_date");
  const ctx = await ownerCtx(body);
  const { sb, house } = ctx;
  const from = body.from_date as string;
  if (!isValidDate(from)) throw new AppError("BAD_DATE", "Invalid date");

  const targets = new Set<string>();
  for (const d of Array.isArray(body.to_dates) ? body.to_dates : []) {
    if (!isValidDate(d)) throw new AppError("BAD_DATE", `Invalid date ${d}`);
    if (d !== from) targets.add(d);
  }
  const weeks = Math.min(Math.max(Number(body.repeat_weeks) || 0, 0), 12);
  for (let w = 1; w <= weeks; w++) targets.add(addDays(from, 7 * w));
  if (!targets.size) throw new AppError("NO_TARGET", "Pick at least one day to copy to");
  if (targets.size > 62) throw new AppError("TOO_MANY", "At most 62 days at a time");

  const slots: Slot[] = Array.isArray(body.slots) && body.slots.length
    ? body.slots.filter((s: string) => s === "morning" || s === "evening")
    : ["morning", "evening"];

  const source = (await menuFor(sb, house.id, from, from)).get(from);
  if (!source || slots.every((s) => !source[s].length)) {
    throw new AppError("EMPTY_SOURCE", "There is no menu on that day to copy");
  }

  const copied: { date: string; slot: Slot }[] = [];
  const skipped: { date: string; slot: Slot; reason: string }[] = [];
  const now = new Date().toISOString();

  for (const date of [...targets].sort()) {
    const off = await offSlots(sb, house.id, date);
    for (const slot of slots) {
      const dishes = source[slot];
      if (!dishes.length) continue;
      if (off[slot]) {
        skipped.push({ date, slot, reason: off[slot]!.type });
        continue;
      }
      must(
        await sb.from("menu").update({ deleted_at: now }).eq("house_id", house.id).eq("date", date)
          .eq("slot", slot).is("deleted_at", null),
      );
      must(await sb.from("menu").insert(dishes.map((d, i) => ({
        house_id: house.id,
        date,
        slot,
        dish_id: d.dish_id,
        notes: d.notes,
        sort_order: i,
      }))));
      copied.push({ date, slot });
    }
  }

  await notifyMenuChange(ctx, copied);
  return { copied, skipped };
});
