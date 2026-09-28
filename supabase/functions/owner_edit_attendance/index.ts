// Owner: add a manual entry or remove (soft delete) an entry, with a note.
// body: { device_id, action: 'add', date, slot, note }
//     | { device_id, action: 'remove', id, note }
import { AppError, handle, requireFields } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { ownerCtx } from "../_shared/auth.ts";
import { Slot, slotExpected, slotRate } from "../_shared/pay.ts";
import { isValidDate, nowIst } from "../_shared/time.ts";

handle(async (body) => {
  requireFields(body, "action");
  const ctx = await ownerCtx(body);
  const { sb, house, settings } = ctx;
  const note = body.note ? String(body.note).slice(0, 300) : null;

  if (body.action === "add") {
    requireFields(body, "date", "slot");
    const date = body.date;
    const slot = body.slot as Slot;
    if (!isValidDate(date)) throw new AppError("BAD_DATE", "Invalid date");
    if (slot !== "morning" && slot !== "evening") throw new AppError("BAD_SLOT", "Invalid slot");
    if (date > nowIst().date) throw new AppError("FUTURE_DATE", "Cannot add attendance for a future day");
    if (!slotExpected(date, slot)) {
      throw new AppError("NOT_EXPECTED_SLOT", "Evening visits are not needed on Saturday/Sunday");
    }
    const ins = await sb.from("attendance").insert({
      house_id: house.id,
      device_id: null,
      date,
      slot,
      scanned_at: new Date().toISOString(),
      amount: slotRate(settings, date, slot),
      is_manual: true,
      note,
    }).select("*").single();
    if (ins.error?.code === "23505") throw new AppError("ALREADY_MARKED", "There is already an entry for this slot");
    return { attendance: must(ins) };
  }

  if (body.action === "remove") {
    requireFields(body, "id");
    const row = must(
      await sb.from("attendance").update({ deleted_at: new Date().toISOString(), note })
        .eq("id", body.id).eq("house_id", house.id).is("deleted_at", null).select("*").maybeSingle(),
    );
    if (!row) throw new AppError("NOT_FOUND", "Entry not found");
    return { attendance: row };
  }

  throw new AppError("BAD_ACTION", "action must be add or remove");
});
