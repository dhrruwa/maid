// Owner: holiday for one date or a range.
// body: { device_id, from, to?, slot: 'morning'|'evening'|'full', paid: bool, note? }
import { AppError, handle, requireFields } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { ownerCtx } from "../_shared/auth.ts";
import { addDays, daysBetween, isValidDate, shortDate } from "../_shared/time.ts";
import { notifyMaid, slotEn, slotKn } from "../_shared/notify.ts";
import { kannadaOf } from "../_shared/translate.ts";

handle(async (body) => {
  requireFields(body, "from", "slot");
  const ctx = await ownerCtx(body);
  const { sb, house } = ctx;
  const from = body.from as string;
  const to = (body.to ?? body.from) as string;
  if (!isValidDate(from) || !isValidDate(to) || to < from) throw new AppError("BAD_DATE", "Invalid dates");
  if (daysBetween(from, to) > 62) throw new AppError("RANGE_TOO_LONG", "Pick at most 2 months at a time");
  if (!["morning", "evening", "full"].includes(body.slot)) throw new AppError("BAD_SLOT", "Invalid slot");
  const paid = body.paid !== false;
  const note = body.note ? String(body.note).slice(0, 300) : null;
  const noteKn = await kannadaOf(sb, note);

  const dates: string[] = [];
  for (let d = from; d <= to; d = addDays(d, 1)) dates.push(d);

  // Replace overlapping holidays on the same days.
  const existing = must(
    await sb.from("holidays").select("id,date,slot").eq("house_id", house.id).is("deleted_at", null)
      .gte("date", from).lte("date", to),
  ) as { id: string; slot: string }[];
  const overlapping = existing.filter((h) => body.slot === "full" || h.slot === "full" || h.slot === body.slot);
  if (overlapping.length) {
    must(
      await sb.from("holidays").update({ deleted_at: new Date().toISOString(), note: "Replaced by new holiday" })
        .in("id", overlapping.map((h) => h.id)),
    );
  }

  const rows = must(
    await sb.from("holidays").insert(dates.map((date) => ({
      house_id: house.id,
      date,
      slot: body.slot,
      paid,
      note,
      note_kn: noteKn,
    }))).select("*"),
  );

  const range = from === to ? shortDate(from) : `${shortDate(from)} – ${shortDate(to)}`;
  await notifyMaid(ctx, {
    en: { title: "Holiday – no need to come", body: `${range} (${slotEn(body.slot)})${note ? ` · ${note}` : ""}` },
    kn: { title: "ರಜೆ – ಬರುವ ಅಗತ್ಯವಿಲ್ಲ", body: `${range} (${slotKn(body.slot)})${note ? ` · ${noteKn ?? note}` : ""}` },
  }, { kind: "holiday" });

  return { holidays: rows };
});
