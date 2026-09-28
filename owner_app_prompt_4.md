# Prompt 1 – Owner App ("Cook Dashboard")

Build a Flutter (Dart) Android app called **"Cook Dashboard"** for a home owner, using **Supabase** as the backend and **Firebase Cloud Messaging** for notifications. **NO login, NO signup, NO OTP.**

This app is only for the owner. A separate **"Cook Attendance"** app (built later) will be used by the maid on her phone and will connect to the same Supabase project. This app creates the full backend.

---

## 1. What the app does
Tracks attendance, salary, menu and history for our home cook, who comes twice a day. She scans a QR code in our house using her own app. This owner app handles setup, dashboard, salary, holidays, leave, daily menu with YouTube recipe links, notifications, payment slips and full history.

---

## 2. UI reference – use Mobbin
Before designing any screen, use the **Mobbin MCP tools** (`search_screens`, `search_flows`, `search_sections`) to find real-app references, and base the layouts on the best patterns found. Do not copy any app's branding, logo or exact design – take layout, spacing and interaction patterns only.

Search Mobbin for these, one per screen:
| Screen | Mobbin search ideas |
|---|---|
| PIN lock | "PIN code entry", "passcode screen" |
| Onboarding / setup steps | "onboarding setup steps", "location permission" |
| Dashboard | "salary dashboard", "earnings summary card", "finance home" |
| Calendar | "attendance calendar", "habit tracker calendar", "month calendar view" |
| Day details | "transaction detail", "day detail bottom sheet" |
| QR display / pairing | "show QR code", "pair device" |
| Menu planner | "meal planner", "recipe list", "add recipe" |
| Leave requests | "approval requests list", "request approve reject" |
| Holidays | "date range picker", "add time off" |
| Activity history | "activity feed", "timeline history", "filter chips" |
| Payment slip | "invoice", "payslip", "receipt share" |
| Settings | "settings list", "notification settings" |

Design direction:
- Clean, warm and friendly (it's a home app, not a corporate tool). Soft cards, rounded corners, generous spacing.
- One accent colour (warm orange or green), neutral background, support light and dark mode.
- Money numbers large and bold; status shown with colour + icon (never colour alone).
- Material 3, bottom navigation with 4 tabs: **Home, Calendar, Menu, History**. Settings from the top-right icon.
- Before writing code, list which Mobbin screens you picked as reference for each screen and why.

---

## 3. First launch setup
1. Set a 4-digit PIN to open the app (store hashed).
2. **"Set house location"** – owner taps while at home; save lat/lng. Default radius 100 m.
3. Generate the **house attendance QR code** (secret token). Owner can save/print/share it to stick in the kitchen.
4. **"Pair maid phone"** – shows a **pairing QR code** on screen (one-time pairing token, valid 10 minutes). The maid scans it with her app to link her phone. Show a 6-digit code below the QR as a backup.

---

## 4. Attendance rules (enforced in Supabase Edge Function, Asia/Kolkata time)
- **Morning slot:** 6:00 AM – 12:00 PM (every day)
- **Evening slot:** 3:00 PM – 9:00 PM (Monday–Friday only)
- One scan per slot per day.
- Valid only if: QR token correct, device is the paired maid phone, GPS within radius, GPS not mocked, time inside a valid slot.
- **Online scans** use server time.
- **Offline scans** (saved on her phone when there was no internet): accept only if uploaded within 12 hours, the saved time falls inside a valid slot, and location was within radius. Mark them as "offline" so the owner can see them.

---

## 5. Pay rules
- **Monday–Friday:** ₹100 per visit (max ₹200/day)
- **Saturday–Sunday:** ₹200 per visit (morning only)
- **Holiday – paid / leave approved as paid:** full pay for the expected visits that day
- **Holiday – unpaid / leave approved as unpaid:** ₹0, not counted as missed
- Rates and time windows are stored in settings and editable.

---

## 6. Salary cycle
- Salary cycle = **1st to the last day of the month**. Salary is paid on the **1st of the next month**. (Example: work from 1–30 Sep is paid on 1 Oct.)
- All "this month" numbers mean the current salary cycle.

### Live salary card (top of Home)
- **"Earned so far (1 Sep – today): ₹X"** – updates immediately after every scan.
- **"Expected by 30 Sep: ₹Y"** – earned so far + remaining expected visits × rate (skip holidays/unpaid leave already set).
- **"Payday: 1 Oct (in N days)"**
- Progress bar: earned so far vs expected total.
- Breakdown: weekday visits × ₹100, weekend visits × ₹200, paid holidays/leave, total.
- **"Lost this month: ₹Z"** – from missed visits.

### Payday
- On the 1st of every month at 9 AM, notify the owner: "Salary due today: ₹X for September".
- Show a "Salary due" banner until the owner taps **"Mark as paid"**.
- If not marked paid within 3 days, remind again.
- When marked paid: save the monthly snapshot and slip, and notify the maid.

---

## 7. Home (dashboard)
- Live salary card (above)
- Today: Morning ✅/❌/⏳, Evening ✅/❌/⏳ (or "Not needed" / "Holiday" / "Leave")
- Today's menu preview
- Counts this month: visits done, missed visits, full days, half days, holidays, leaves
- Pending leave requests (if any)

## 8. Calendar
- Month calendar colours: **Green** = all visits done, **Yellow** = partial, **Red** = missed, **Blue** = holiday, **Purple** = leave, **Grey** = future. Small food icon on days with a menu set.
- Tap a day → bottom sheet with scan times, distance from house, online/offline, amount, menu of that day, holiday/leave details.
- Switch to previous months.
- Add/remove an entry manually with a note (shown as "manual").

---

## 9. Holidays (set by owner)
- Select a date or date range, choose Morning / Evening / Full day, mark **Paid** or **Unpaid**, optional note (e.g. "We are travelling").
- Maid app shows these days as "Holiday – no need to come" and she is notified.

## 10. Leave requests (from maid)
- Maid sends a leave request from her app (date, morning/evening/full day, optional reason).
- Owner gets a push notification and sees it in a "Leave requests" list.
- Owner can **Approve as Paid**, **Approve as Unpaid**, or **Reject**. Maid is notified of the decision.

---

## 11. Daily menu (set by owner)
- Plan what to cook for any date, separately for Morning and Evening.
- Each meal can have one or more dishes. Each dish has:
  - Dish name (e.g. "Palak Paneer")
  - YouTube link for how to cook it (optional)
  - Notes (optional, e.g. "Less spicy", "Make for 4 people")
- Show a YouTube thumbnail preview when a link is pasted; validate it's a YouTube URL.
- Save dishes to a **"My dishes"** list to pick again later without retyping.
- **"Copy menu"**: copy a day's menu to another day, or repeat it weekly.
- When a menu is added or changed for today or tomorrow, notify the maid: "Tomorrow morning: Palak Paneer, Chapati".
- Skip menu for slots that are holidays or approved leave.

---

## 12. Notifications (to owner)
- Maid marked attendance: "Morning attendance marked at 7:42 AM"
- New leave request
- Offline scan uploaded
- Salary due on the 1st (and reminder)
- Owner can turn each type on/off in settings.

---

## 13. Monthly payment slip
- For any month, generate a slip (PDF and image): house name, maid name, month, table of each day (morning/evening status), counts, holidays and leaves, total amount, paid/unpaid status and paid date.
- **"Share on WhatsApp"** button (share sheet).
- The maid can see and download the same slip in her app.

---

## 14. History (keep everything, never lose data)
- Nothing is ever permanently deleted. All deletes are soft deletes (set `deleted_at`, hide from normal views).
- Every create, edit and delete is recorded in an activity log: who did it (owner / maid / system), what changed, old value, new value, and when.
- Covers: attendance scans (online, offline, manual), manual edits, holidays, leave requests and decisions, menu and dish changes, payments, settings changes, pairing/unpairing, QR regeneration.

### History tab
- **Activity**: timeline of all events, newest first, e.g.
  - "29 Sep, 7:42 AM – Maid marked morning attendance (₹100)"
  - "29 Sep, 9:10 PM – Owner changed menu for 30 Sep morning: Upma → Poha"
  - "28 Sep, 6:05 PM – Owner removed evening entry (note: scanned by mistake)"
- Filters: type (attendance, menu, leave, holiday, payment, settings), date range, who did it. Search by dish name or note.
- Tap an event to see old vs new values. **"Restore"** on deleted items.
- **Payments**: every month with total, paid/unpaid, paid date and slip.
- **Menu history**: what was cooked on any past date; "Most cooked dishes" with counts.
- **Leave history**: all requests with status and decision date.
- Month summaries are frozen when marked paid, so old slips never change even if rates change later.
- **"Export all data"**: download everything as Excel/CSV.

---

## 15. Settings
- Change PIN, pay rates, time windows, radius
- Notification preferences
- See paired maid phone, **"Unpair maid phone"**
- Regenerate attendance QR (old one stops working)
- Export data

---

## 16. Supabase (create everything)

### Tables
All tables have `created_at` and `updated_at`.
- `house` (id, name, lat, lng, radius_m, qr_token, owner_pin_hash, owner_device_id, owner_fcm_token)
- `pairing_tokens` (token, code_6digit, house_id, expires_at, used)
- `cook_device` (id, house_id, device_id, name, fcm_token, paired_at, active)
- `settings` (house_id, weekday_rate, weekend_rate, morning_start, morning_end, evening_start, evening_end, notify_scan, notify_leave, notify_offline, notify_payday, notify_menu)
- `attendance` (id, house_id, device_id, date, slot ['morning','evening'], scanned_at, uploaded_at, lat, lng, distance_m, amount, is_offline, is_manual, note, deleted_at) – unique on (house_id, date, slot) where deleted_at is null
- `holidays` (id, house_id, date, slot ['morning','evening','full'], paid boolean, note, deleted_at)
- `leave_requests` (id, house_id, device_id, date, slot, reason, status ['pending','approved_paid','approved_unpaid','rejected'], decided_at, deleted_at)
- `dishes` (id, house_id, name, youtube_url, notes, deleted_at)
- `menu` (id, house_id, date, slot ['morning','evening'], dish_id, notes, sort_order, deleted_at)
- `payments` (id, house_id, month, total_amount, paid_on)
- `monthly_snapshots` (id, house_id, month, rates_used jsonb, summary jsonb, slip_url)
- `activity_log` (id, house_id, actor ['owner','maid','system'], action ['create','update','delete','restore'], entity_type, entity_id, old_value jsonb, new_value jsonb, note, created_at)

### History rules
- Write to `activity_log` automatically using Postgres triggers on every table.
- `activity_log` is append-only: no update or delete allowed.
- Store generated slips in Supabase Storage.

### Edge Functions
- create_house, generate_pairing_token, pair_cook
- mark_attendance (online + offline), owner_edit_attendance
- set_holiday, request_leave, decide_leave
- save_dish, set_menu, copy_menu, get_menu
- get_month_summary, get_live_salary, generate_slip, mark_paid
- get_activity, restore_item, export_data
- send_notification (FCM)

The maid app will call: pair_cook, mark_attendance, request_leave, get_menu, get_month_summary, get_live_salary, generate_slip.

### Scheduled functions
- **maid_reminder** (every 30 min): if the maid hasn't scanned by 11:30 AM (morning) or 8:30 PM (evening, weekdays only), and that slot isn't a holiday or approved leave, send her a reminder.
- **payday_reminder** (daily 9 AM): remind the owner on the 1st, and again on the 4th if still unpaid.

### Security
- Apps use the anon key. RLS blocks direct table writes.
- All writes go through Edge Functions that verify the owner device ID or the paired maid device ID.
- The maid can only read her own attendance, menu, leave, salary and slips.

---

## 17. Packages
supabase_flutter, firebase_core, firebase_messaging, qr_flutter, geolocator, shared_preferences, table_calendar, intl, crypto, share_plus, pdf, printing, youtube_player_flutter, url_launcher, excel

---

## 18. Deliverables
1. The Mobbin reference list (screen → reference picked).
2. Full app code with a clean folder structure.
3. SQL for all tables, triggers and RLS policies.
4. All Edge Functions and scheduled functions.
5. Firebase setup.
6. Beginner-friendly step-by-step guide: create the Supabase project, run the SQL, deploy functions, set up Firebase, add keys, build the APK and install it.
7. A short **API document** describing the Edge Functions the maid app will use (inputs and outputs), to give to the maid app.
