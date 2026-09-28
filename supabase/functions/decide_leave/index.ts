// Owner: approve as paid / approve as unpaid / reject a leave request.
// body: { device_id, id, decision: 'approved_paid' | 'approved_unpaid' | 'rejected' }
import { AppError, handle, requireFields } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { ownerCtx } from "../_shared/auth.ts";
import { shortDate } from "../_shared/time.ts";
import { notifyMaid, slotEn, slotKn } from "../_shared/notify.ts";

const TEXT = {
  approved_paid: { en: "Leave approved (paid)", kn: "ರಜೆ ಅನುಮೋದಿಸಲಾಗಿದೆ (ಸಂಬಳ ಸಹಿತ)" },
  approved_unpaid: { en: "Leave approved (unpaid)", kn: "ರಜೆ ಅನುಮೋದಿಸಲಾಗಿದೆ (ಸಂಬಳ ರಹಿತ)" },
  rejected: { en: "Leave not approved", kn: "ರಜೆ ಅನುಮೋದನೆ ಆಗಿಲ್ಲ" },
} as const;

handle(async (body) => {
  requireFields(body, "id", "decision");
  const ctx = await ownerCtx(body);
  const decision = body.decision as keyof typeof TEXT;
  if (!(decision in TEXT)) throw new AppError("BAD_DECISION", "Invalid decision");

  const row = must(
    await ctx.sb.from("leave_requests")
      .update({ status: decision, decided_at: new Date().toISOString() })
      .eq("id", body.id).eq("house_id", ctx.house.id).is("deleted_at", null)
      .select("*").maybeSingle(),
  ) as { date: string; slot: string } | null;
  if (!row) throw new AppError("NOT_FOUND", "Leave request not found");

  await notifyMaid(ctx, {
    en: { title: TEXT[decision].en, body: `${shortDate(row.date)} (${slotEn(row.slot)})` },
    kn: { title: TEXT[decision].kn, body: `${shortDate(row.date)} (${slotKn(row.slot)})` },
  }, { kind: "leave" });

  return { leave: row };
});
