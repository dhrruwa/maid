// Family app: book or cancel one meal (until the slot's window starts).
// body: { device_id, date, slot: 'morning'|'evening', book: boolean, note? }
// book: true  → booked (a note, when sent, replaces the booking's note; "" clears it)
// book: false → cancelled (no-op when not booked)
// → the updated SLOT for that date, at the top level and also as `slot`:
//   { date, items, off, cutoff, open, booked, note, bookings, slot: SLOT }
// Errors: BAD_DATE (not today..today+13), BAD_SLOT, SLOT_OFF { off },
//         BOOKING_CLOSED { cutoff }.
import { AppError, handle, requireFields } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { memberCtx } from "../_shared/auth.ts";
import { BOOK_AHEAD_DAYS, bookableDate, cleanNote, memberDays, slotCutoffMs } from "../_shared/family.ts";
import { offSlots } from "../_shared/menu.ts";
import { Slot } from "../_shared/pay.ts";
import { addDays, isValidDate, nowIst } from "../_shared/time.ts";
import { kannadaOf } from "../_shared/translate.ts";

handle(async (body) => {
  requireFields(body, "date", "slot", "book");
  const ctx = await memberCtx(body);
  const { sb, house, settings } = ctx;
  const member = ctx.member!;
  const now = nowIst();
  const nowMs = Date.parse(now.iso);

  const date = body.date as string;
  if (!isValidDate(date) || !bookableDate(date, now.date)) {
    throw new AppError("BAD_DATE", `Meals can be booked from today up to ${BOOK_AHEAD_DAYS} days ahead`, {
      from: now.date,
      to: addDays(now.date, BOOK_AHEAD_DAYS),
    });
  }
  if (body.slot !== "morning" && body.slot !== "evening") {
    throw new AppError("BAD_SLOT", "slot must be morning or evening");
  }
  const slot = body.slot as Slot;
  const book = body.book === true || body.book === "true";

  const off = (await offSlots(sb, house.id, date))[slot];
  if (off) throw new AppError("SLOT_OFF", "No meal is cooked in this slot", { off });
  const cutoffMs = slotCutoffMs(settings, date, slot);
  if (nowMs >= cutoffMs) {
    throw new AppError("BOOKING_CLOSED", "Booking for this meal has closed", {
      cutoff: new Date(cutoffMs).toISOString(),
    });
  }

  const active = () =>
    sb.from("meal_bookings").select("id,note").eq("member_id", member.id).eq("date", date)
      .eq("slot", slot).is("cancelled_at", null).maybeSingle();
  const setNote = async (id: string, note: string | null) =>
    await sb.from("meal_bookings").update({ note, note_kn: await kannadaOf(sb, note) }).eq("id", id)
      .is("cancelled_at", null);

  const existing = must(await active()) as { id: string; note: string | null } | null;
  const hasNote = Object.prototype.hasOwnProperty.call(body, "note");
  const note = cleanNote(body.note);

  if (book) {
    if (existing) {
      if (hasNote && existing.note !== note) must(await setNote(existing.id, note));
    } else {
      const ins = await sb.from("meal_bookings")
        .insert({ house_id: house.id, member_id: member.id, date, slot, note, note_kn: await kannadaOf(sb, note) });
      if (ins.error?.code === "23505") {
        // Booked by a parallel request (double tap): keep it, apply the note.
        const again = must(await active()) as { id: string; note: string | null } | null;
        if (again && hasNote && again.note !== note) must(await setNote(again.id, note));
      } else {
        must(ins);
      }
    }
  } else if (existing) {
    must(
      await sb.from("meal_bookings").update({ cancelled_at: new Date().toISOString() })
        .eq("id", existing.id).is("cancelled_at", null),
    );
  }

  const [day] = await memberDays(sb, house.id, settings, member.id, date, date, nowMs);
  const s = day.slots[slot];
  return { date, ...s, slot: s };
});
