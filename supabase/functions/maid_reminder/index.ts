// Scheduled every 30 min. 30 minutes before a slot closes (11:30 AM / 8:30 PM
// with default windows), remind the maid if she has not scanned and the slot
// is not a holiday / approved leave. Each reminder is sent once per day.
import { handle, requireCronSecret } from "../_shared/http.ts";
import { db, must } from "../_shared/db.ts";
import { activeCook, Ctx, House, Settings } from "../_shared/auth.ts";
import { offSlots } from "../_shared/menu.ts";
import { Slot, slotWindow } from "../_shared/pay.ts";
import { minToLabel, nowIst } from "../_shared/time.ts";
import { KN, notifyMaid } from "../_shared/notify.ts";

handle(async (_body, req) => {
  requireCronSecret(req);
  const sb = db("system");
  const now = nowIst();
  const houses = must(await sb.from("house").select("*")) as House[];
  const sent: string[] = [];

  for (const house of houses) {
    const cook = await activeCook(sb, house.id);
    if (!cook?.fcm_token) continue;
    const settings = must(await sb.from("settings").select("*").eq("house_id", house.id).single()) as Settings;
    const ctx: Ctx = { role: "owner", sb, house, settings, cook };

    for (const slot of ["morning", "evening"] as Slot[]) {
      const [, end] = slotWindow(settings, slot);
      if (now.minutes < end - 30 || now.minutes >= end) continue;

      const off = (await offSlots(sb, house.id, now.date))[slot];
      if (off) continue; // holiday, approved leave, or weekend evening

      const done = must(
        await sb.from("attendance").select("id").eq("house_id", house.id).eq("date", now.date)
          .eq("slot", slot).is("deleted_at", null).maybeSingle(),
      );
      if (done) continue;

      const kind = `maid_${slot}`;
      const claim = await sb.from("sent_reminders").insert({ house_id: house.id, kind, day: now.date });
      if (claim.error) continue; // already sent today

      const endLabel = minToLabel(end);
      await notifyMaid(ctx, {
        en: {
          title: "Attendance reminder",
          body: `You have not scanned for the ${slot} yet. Please scan before ${endLabel}.`,
        },
        kn: {
          title: "ಹಾಜರಾತಿ ನೆನಪು",
          body: `ನೀವು ಇನ್ನೂ ${slot === "morning" ? KN.morning : KN.evening} ಹಾಜರಾತಿ ಸ್ಕ್ಯಾನ್ ಮಾಡಿಲ್ಲ. ${endLabel} ಒಳಗೆ ಸ್ಕ್ಯಾನ್ ಮಾಡಿ.`,
        },
      }, { kind: "reminder", slot });
      sent.push(`${house.id}:${slot}`);
    }
  }
  return { sent };
});
