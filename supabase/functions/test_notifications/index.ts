// Sends one of every notification this phone's app can get, to this phone, so
// its user can check they all arrive:
//   owner phone          → the Owner app's (Settings → Send test notifications)
//   family member phone  → the Family app's
// Same titles, texts and `kind` as the real ones, with "(test)" at the end.
// Sent even when a kind is switched off in Settings. `delay_seconds` (0–10)
// gives time to leave the app: in the app they only show as snackbars,
// outside it as real notifications.
// body: { device_id, delay_seconds? }  → { app: "owner" | "family", sent, total }
import { AppError, handle } from "../_shared/http.ts";
import { Ctx, memberCtx, ownerCtx } from "../_shared/auth.ts";
import { sendPush } from "../_shared/fcm.ts";
import { addDays, minToLabel, monthName, nowIst, prevMonth, shortDate, timeToMin } from "../_shared/time.ts";

type Push = [title: string, body: string, data: Record<string, string>];

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** mark_attendance, request_leave, payday_reminder and pair_cook. */
function ownerPushes(ctx: Ctx): Push[] {
  const now = nowIst();
  const cook = ctx.cook?.name ?? "Maid";
  const rate = ctx.settings.weekday_rate;
  const lastMonth = monthName(prevMonth(now.date.slice(0, 7)));
  const at = minToLabel(7 * 60 + 5); // 7:05 AM
  const earned = 24 * rate;
  return [
    ["Morning attendance marked", `Morning attendance marked at ${at} · ₹${rate}`, { kind: "scan", date: now.date }],
    [
      "Offline scan uploaded",
      `${cook}: Morning at ${at} (uploaded ${minToLabel(now.minutes)}) · ₹${rate}`,
      { kind: "offline", date: now.date },
    ],
    ["New leave request", `${cook}: ${shortDate(addDays(now.date, 1))} (Full day) – family function`, {
      kind: "leave",
    }],
    // On the 1st, and a reminder on the 4th.
    ["Salary due today", `₹${earned} for ${lastMonth}`, { kind: "payday" }],
    ["Reminder: salary not marked as paid", `₹${earned} for ${lastMonth}`, { kind: "payday" }],
    ["Maid phone paired", `${cook}'s phone is now linked.`, { kind: "pair" }],
  ];
}

/** family_notify: a menu set or changed, several menus changed, a booking reminder. */
function familyPushes(ctx: Ctx): Push[] {
  const date = addDays(nowIst().date, 1);
  // Booking closes when cooking starts.
  const closesMorning = minToLabel(timeToMin(ctx.settings.morning_start));
  const closesEvening = minToLabel(timeToMin(ctx.settings.evening_start));
  return [
    [
      "Menu for tomorrow morning",
      `Idli, Sambar. Book before ${closesMorning} if you're eating.`,
      { kind: "family_menu", date, slot: "morning" },
    ],
    [
      "2 menus updated",
      "tomorrow morning, tomorrow evening. Tap to see them and book.",
      { kind: "family_menu", date, slot: "morning" },
    ],
    [
      "Eating tomorrow evening?",
      `Chapati, Dal. Book before ${closesEvening} so the cook knows how many to cook for.`,
      { kind: "family_book", date, slot: "evening" },
    ],
  ];
}

handle(async (body) => {
  // The owner phone, or else a family member's phone.
  const ctx = await ownerCtx(body).catch((e) => {
    if (e instanceof AppError && e.code === "NOT_OWNER") return memberCtx(body);
    throw e;
  });
  const app = ctx.role === "owner" ? "owner" : "family";
  const token = app === "owner" ? ctx.house.owner_fcm_token : ctx.member?.fcm_token;
  if (!token) {
    throw new AppError(
      "NO_PUSH_TOKEN",
      `This phone isn't registered for notifications yet. Allow notifications for the ${
        app === "owner" ? "Owner" : "Family"
      } app, close and reopen it, then try again.`,
    );
  }

  const delay = Math.min(Math.max(Number(body.delay_seconds) || 0, 0), 10);
  if (delay > 0) await sleep(delay * 1000);

  const pushes = app === "owner" ? ownerPushes(ctx) : familyPushes(ctx);
  let sent = 0;
  for (const [title, text, data] of pushes) {
    if (await sendPush(token, title, text + " (test)", { ...data, test: "1" })) sent++;
    await sleep(400); // so they show up in this order
  }
  if (sent === 0) {
    throw new AppError(
      "PUSH_FAILED",
      "No notification could be sent. Firebase refused this phone's token or isn't set up on the server.",
    );
  }
  return { app, sent, total: pushes.length };
});
