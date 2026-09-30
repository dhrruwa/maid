// Owner phone: sends one of every notification the owner can get, to this
// phone, so they can check they all arrive (Settings → Send test notifications).
// Same titles, texts and `kind` as the real ones, with "(test)" at the end.
// Sent even when a kind is switched off in Settings. `delay_seconds` (0–10)
// gives the owner time to leave the app: in the app they only show as
// snackbars, outside it as real notifications.
// body: { device_id, delay_seconds? }  → { sent, total }
import { AppError, handle } from "../_shared/http.ts";
import { ownerCtx } from "../_shared/auth.ts";
import { sendPush } from "../_shared/fcm.ts";
import { addDays, minToLabel, monthName, nowIst, prevMonth, shortDate } from "../_shared/time.ts";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

handle(async (body) => {
  const ctx = await ownerCtx(body);
  const token = ctx.house.owner_fcm_token;
  if (!token) {
    throw new AppError(
      "NO_PUSH_TOKEN",
      "This phone isn't registered for notifications yet. Allow notifications for the Owner app, close and reopen it, then try again.",
    );
  }

  const delay = Math.min(Math.max(Number(body.delay_seconds) || 0, 0), 10);
  if (delay > 0) await sleep(delay * 1000);

  const now = nowIst();
  const cook = ctx.cook?.name ?? "Maid";
  const rate = ctx.settings.weekday_rate;
  const lastMonth = monthName(prevMonth(now.date.slice(0, 7)));
  const at = minToLabel(7 * 60 + 5); // 7:05 AM
  const earned = 24 * rate;
  const test = " (test)";

  const pushes: [string, string, Record<string, string>][] = [
    // mark_attendance
    ["Morning attendance marked", `Morning attendance marked at ${at} · ₹${rate}`, { kind: "scan", date: now.date }],
    [
      "Offline scan uploaded",
      `${cook}: Morning at ${at} (uploaded ${minToLabel(now.minutes)}) · ₹${rate}`,
      { kind: "offline", date: now.date },
    ],
    // request_leave
    ["New leave request", `${cook}: ${shortDate(addDays(now.date, 1))} (Full day) – family function`, { kind: "leave" }],
    // payday_reminder, on the 1st and on the 4th
    ["Salary due today", `₹${earned} for ${lastMonth}`, { kind: "payday" }],
    ["Reminder: salary not marked as paid", `₹${earned} for ${lastMonth}`, { kind: "payday" }],
    // pair_cook
    ["Maid phone paired", `${cook}'s phone is now linked.`, { kind: "pair" }],
  ];

  let sent = 0;
  for (const [title, text, data] of pushes) {
    if (await sendPush(token, title, text + test, { ...data, test: "1" })) sent++;
    await sleep(400); // so they show up in this order
  }
  if (sent === 0) {
    throw new AppError(
      "PUSH_FAILED",
      "No notification could be sent. Firebase refused this phone's token or isn't set up on the server.",
    );
  }
  return { sent, total: pushes.length };
});
