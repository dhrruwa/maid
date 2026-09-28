# Prompt 2 – Maid App ("Cook Attendance")

Build a Flutter (Dart) Android app called **"Cook Attendance"** for our home cook, using an **existing Supabase project** and **Firebase Cloud Messaging**. **NO login, NO signup, NO OTP.**

The Supabase project, database and Edge Functions were already created by our owner app ("Cook Dashboard"). Use these existing Edge Functions:
- `pair_cook(pairing_token or 6-digit code, device_id, name, fcm_token)`
- `mark_attendance(qr_token, device_id, lat, lng, is_mocked, scanned_at, is_offline)`
- `request_leave(device_id, date, slot, reason)`
- `get_menu(device_id, date)`
- `get_month_summary(device_id, month)`
- `get_live_salary(device_id)`
- `generate_slip(device_id, month)`

**[Paste the API document from the owner app here]**

---

## 1. UI reference – use Mobbin
Before designing any screen, use the **Mobbin MCP tools** (`search_screens`, `search_flows`, `search_sections`) to find real-app references, and base the layouts on the best patterns found. Do not copy any app's branding, logo or exact design – take layout, spacing and interaction patterns only.

Search Mobbin for these, one per screen:
| Screen | Mobbin search ideas |
|---|---|
| Pairing / first launch | "scan QR to connect", "pair device onboarding" |
| Home | "earnings home screen", "daily tasks home", "check-in app" |
| QR scanner | "QR scanner camera", "scan to check in" |
| Success / failure | "payment success", "check-in success", "error state" |
| Menu card + video | "recipe detail", "video recipe", "today's meal" |
| Leave request | "request time off", "leave application form" |
| Salary / history | "earnings history", "monthly statement", "payslip" |

Design direction:
- **Very simple** – the user may not be comfortable with phones. Big buttons (minimum 56 px tall), big text, icons next to every label, very few choices per screen.
- One main action on the home screen: the big **"Scan QR"** button.
- Warm, friendly colours matching the owner app (warm orange or green accent), light mode by default.
- Status shown with colour + icon + text (never colour alone).
- **English + Kannada** toggle, easy to find.
- Must work smoothly on low-end Android phones.
- Before writing code, list which Mobbin screens you picked as reference for each screen and why.

---

## 2. First launch – pairing
- Ask for her name.
- Big **"Scan pairing QR"** button – she scans the QR shown on the owner's phone.
- Small **"Enter code instead"** link for the 6-digit backup code.
- Generate a unique device ID, save it locally (shared_preferences), get the FCM token, call `pair_cook`.
- After pairing, always open straight to the home screen.

---

## 3. Home screen (top to bottom)

### My salary card
- Big text: **"Earned so far: ₹X"** (1st of this month till today) – updates right after every scan with a small animation (+₹100 / +₹200).
- "You can earn up to ₹Y by the end of the month if you come every day."
- **"Salary on 1 Oct (in N days)"**
- Progress bar: earned vs possible.
- Tap for a simple breakdown: weekday visits, weekend visits, paid holidays/leave.
- When the owner marks salary as paid, show **"September salary ₹X paid on 1 Oct ✅"**.
- Salary cycle is 1st to the last day of the month, paid on the 1st of the next month.
- Use `get_live_salary(device_id)`.

### Today
- Morning ✅/❌/⏳, Evening ✅/❌/⏳
- Show "Not needed today" for Saturday/Sunday evening.
- Show "Holiday – no need to come" or "Leave approved" when applicable.

### Big "Scan QR" button

### What to cook
- Card for the current/next slot: Morning card from midnight to 12 PM, Evening card from 12 PM to 9 PM.
- Dish name(s), the owner's notes, and a YouTube thumbnail.
- Tap the thumbnail to play the video inside the app; **"Open in YouTube"** button as backup.
- **"Tomorrow"** tab to see the next day's menu.
- If no menu is set: "No menu set – please ask the owner".
- Use `get_menu(device_id, date)`.

### Bottom buttons
- **Request leave**, **My history**

---

## 4. Scan flow
- Location permission required. If off, show "Please turn on location" with a button to open settings.
- Scan the house QR, get GPS location, check if location is mocked.
- **Internet available:** call `mark_attendance` and show the result.
- **No internet:** save the scan locally (QR token, time, lat, lng, is_mocked) and show "Saved – will upload when internet is back". Upload automatically when the network returns (connectivity_plus + background retry), then show the result.
- **Success:** big green screen with time, morning/evening, ₹ earned.
- **Failure:** big red screen with a simple reason, e.g.:
  - "You are not at the house"
  - "Evening not needed on Saturday"
  - "Morning already marked"
  - "Time is over for morning (6 AM – 12 PM)"

---

## 5. Leave request
- Pick date, Morning / Evening / Full day, optional reason, **Send**.
- List of her requests with status: Waiting / Approved (paid or unpaid) / Rejected.
- Use `request_leave`.

---

## 6. My history
- Month-by-month list: visits, amount earned, paid or not, paid date.
- Tap a month to see every day's attendance and view/download/share that month's slip.
- Past menus: what she cooked on any past date.
- Leave history: all her requests with status.
- She can only see her own data – not the owner's activity log or settings.
- Use `get_month_summary`, `get_menu`, `generate_slip`.

---

## 7. Notifications (to maid)
- Reminder if she hasn't scanned by 11:30 AM or 8:30 PM (sent by the server)
- Leave approved / rejected
- New holiday added by the owner
- Menu added or changed for today/tomorrow
- Salary marked as paid

---

## 8. Packages
supabase_flutter, firebase_core, firebase_messaging, mobile_scanner, geolocator, shared_preferences, connectivity_plus, intl, share_plus, printing, youtube_player_flutter, url_launcher

---

## 9. Deliverables
1. The Mobbin reference list (screen → reference picked).
2. Full app code with a clean folder structure.
3. Kannada + English translation files.
4. Beginner-friendly steps to add the Supabase keys and Firebase config, build the APK, and install it on her phone.
