# Cook Attendance – Edge Function API (for the maid app)

The owner app ("Cook Dashboard") created the Supabase project, database and all Edge Functions. The maid app ("Cook Attendance") only calls the functions listed below.

## How to call

- **URL:** `POST https://<project-ref>.supabase.co/functions/v1/<function_name>`
- **Headers:** `Content-Type: application/json`. Also send the anon key as `apikey` and `Authorization: Bearer <anon key>`; `supabase_flutter` adds these for you through `Supabase.instance.client.functions.invoke(name, body: {...})`.
- **Body:** JSON. **Every call includes `device_id`**: a random secret string (at least 16 characters) that the maid app creates once and keeps in `shared_preferences`. It identifies the paired phone. Treat it like a password.
- **Success:** HTTP 200 with `{ "ok": true, ...result }`.
- **Error:** `{ "ok": false, "error": { "code": "STRING", "message": "English text", "details": { ... } } }`.
  - Business errors come back with HTTP 200 so the app can read them directly.
  - "Not paired" comes back as HTTP 401, which `supabase_flutter` raises as a `FunctionException`. Read `e.details` to get the same JSON.
  - The app should translate `code`; `message` is only an English fallback.

All dates are `YYYY-MM-DD` and months are `YYYY-MM`, both in **Asia/Kolkata** time. Timestamps are ISO-8601 UTC.

Slot values are `"morning"` and `"evening"`. Leave requests can also use `"full"`.

QR contents:

| QR | Content |
|---|---|
| House attendance QR (printed, in the kitchen) | `CDHOUSE:<qr_token>` |
| Pairing QR (shown on the owner's phone, valid 10 min) | `CDPAIR:<token>` |

---

## pair_cook
Links this phone to the house. No `device_id` check is done before this call.

| Input | Type | Notes |
|---|---|---|
| `device_id` | string | this phone's ID |
| `pairing_token` | string | from the pairing QR (with or without the `CDPAIR:` prefix), **or** |
| `code` | string | the 6-digit backup code |
| `name` | string | the cook's name |
| `fcm_token` | string? | Firebase token for push notifications |
| `lang` | `"en"` \| `"kn"` | language for her push notifications |

**Returns:** `{ house_name, name, rates: { weekday_rate, weekend_rate, morning_start, morning_end, evening_start, evening_end } }`

**Errors:** `PAIRING_INVALID` (wrong or expired code), `MISSING_FIELD`.

Pairing a new phone automatically unpairs the old one.

## mark_attendance
Records a visit after scanning the house QR.

| Input | Type | Notes |
|---|---|---|
| `device_id` | string | |
| `qr_token` | string | the scanned value (the `CDHOUSE:` prefix is accepted) |
| `lat`, `lng` | number | GPS position at scan time |
| `is_mocked` | bool | from `Position.isMocked` |
| `is_offline` | bool | `true` when uploading a scan that was saved without internet |
| `scanned_at` | ISO string | **required when `is_offline` is true** (the time of the real scan) |

Rules (enforced on the server):
- The QR is correct, the phone is paired, the GPS isn't mocked, and the position is within the house radius.
- The time is inside a slot: morning 6 AM–12 PM every day; evening 3 PM–9 PM Monday to Friday only. The owner can change these windows.
- One scan per slot per day.
- **Online scans** use server time.
- **Offline scans** use `scanned_at`, must be uploaded within 12 hours, and are marked "offline" for the owner.

**Returns:**
```json
{
  "attendance": { "id", "date", "slot", "scanned_at", "time_label": "7:42 AM", "amount": 100,
                  "distance_m": 12, "is_offline": false },
  "earned_so_far": 1300,
  "salary": { ...same as get_live_salary.salary }
}
```

**Errors (with `details`):**

| code | details | show the cook |
|---|---|---|
| `WRONG_QR` | | "This is not the house QR" |
| `NOT_AT_HOUSE` | `distance_m`, `radius_m` | "You are not at the house" |
| `MOCK_LOCATION` | | "Fake location found" |
| `EVENING_NOT_NEEDED` | `day` ("Saturday"/"Sunday") | "Evening not needed on Saturday" |
| `ALREADY_MARKED` | `slot` | "Morning already marked" |
| `TOO_EARLY` | `opens` ("6 AM"), `window` | "Too early. Morning starts at 6 AM" |
| `MORNING_OVER` | `window` ("6 AM – 12 PM"), `evening_opens` | "Time is over for morning (6 AM – 12 PM)" |
| `EVENING_OVER` | `window` | "Time is over for evening (3 PM – 9 PM)" |
| `OFFLINE_TOO_OLD` | | "This saved scan is older than 12 hours" |
| `BAD_TIME` | | phone clock is wrong / missing `scanned_at` |
| `HOUSE_LOCATION_NOT_SET` | | owner has not set the location |
| `NOT_PAIRED` (HTTP 401) | | send her back to pairing |

## request_leave
| Input | Type |
|---|---|
| `device_id` | string |
| `date` | `YYYY-MM-DD` (today or later) |
| `slot` | `"morning"` \| `"evening"` \| `"full"` |
| `reason` | string? (max 300) |

**Returns:** `{ leave: { id, date, slot, reason, status: "pending", created_at, ... } }`. The owner gets a push notification.

**Errors:** `PAST_DATE`, `LEAVE_EXISTS`, `BAD_SLOT`.

## list_leave
Her leave requests, newest first.

**Input:** `{ device_id, status?: "pending" | "approved_paid" | "approved_unpaid" | "rejected" }`

**Returns:** `{ leaves: [ { id, date, slot, reason, status, decided_at, created_at } ] }`

## get_menu
**Input:** `{ device_id, date }`

**Returns:**
```json
{
  "date": "2026-09-30",
  "morning": {
    "items": [ { "menu_id", "dish_id", "name": "Palak Paneer", "youtube_url": "https://youtu.be/…",
                 "dish_notes": "Use less oil", "notes": "Make for 4 people" } ],
    "off": null
  },
  "evening": {
    "items": [],
    "off": { "type": "holiday" | "leave" | "not_needed", "paid": true, "note": "We are travelling" }
  }
}
```
When `off` is set, she doesn't need to come for that slot (holiday, approved leave, or a Saturday/Sunday evening). Show that instead of the menu.

## get_live_salary
**Input:** `{ device_id }`

**Returns:**
```json
{
  "house_name": "Home", "maid_name": "Lakshmi",
  "salary": {
    "month": "2026-09", "from": "2026-09-01", "today": "2026-09-29", "cycle_end": "2026-09-30",
    "earned": 2400,              // 1st → today, including paid holidays/leave already passed
    "expected_total": 2800,      // earned + every remaining expected visit
    "remaining_expected": 400,
    "lost": 200,                 // missed visits × rate
    "payday": "2026-10-01", "days_to_payday": 2,
    "breakdown": { "weekday_visits", "weekday_rate", "weekday_amount",
                   "weekend_visits", "weekend_rate", "weekend_amount",
                   "paid_off_slots", "paid_off_amount", "total" },
    "counts": { "visits_done", "missed", "full_days", "half_days", "holidays", "leaves", ... },
    "last_payment": { "month": "2026-08", "total_amount": 2600, "paid_on": "2026-09-01" } | null,
    "today_info": { ...one day object, see get_month_summary }
  }
}
```

## get_month_summary
**Input:** `{ device_id, month: "YYYY-MM" }`

**Returns:** `{ summary }`, where:
```json
{
  "month": "2026-09", "house_name", "maid_name", "frozen": false,
  "rates": { "weekday_rate", "weekend_rate", "morning_start", "morning_end", "evening_start", "evening_end" },
  "days": [ {
      "date": "2026-09-29", "dow": 2,
      "status": "green|yellow|red|blue|purple|grey|none",
      "amount": 200, "has_menu": true,
      "menu": { "morning": [dish…], "evening": [dish…] },
      "slots": {
        "morning": { "state": "done|missed|pending|upcoming|holiday_paid|holiday_unpaid|leave_paid|leave_unpaid|not_needed|none",
                     "rate": 100, "amount": 100,
                     "attendance": { "id", "scanned_at", "uploaded_at", "distance_m", "is_offline", "is_manual", "note", "amount" } | null,
                     "holiday": { "id", "paid", "note", "slot" } | null,
                     "leave": { "id", "status", "reason", "slot" } | null },
        "evening": { … }
      }
  } ],
  "counts": { "visits_done", "missed", "full_days", "half_days", "holidays", "leaves",
              "weekday_visits", "weekend_visits", "paid_off_slots" },
  "totals": { "earned", "weekday_amount", "weekend_amount", "paid_off_amount",
              "remaining_expected", "expected_total", "lost" },
  "holidays": [ … ], "leaves": [ … ],
  "payment": { "paid_on", "total_amount" } | null
}
```
Months that have been paid come back **frozen**: the saved snapshot, never recalculated.

## list_months
**Input:** `{ device_id }`

**Returns:** `{ months: [ { month, visits, missed, total, paid, paid_on, paid_amount, has_slip, is_current } ] }`, newest first.

## generate_slip
**Input:** `{ device_id, month }`

**Returns:** `{ url, month, paid, total }`. `url` is a signed link to the PDF slip that is valid for 1 hour. Download it with `http`, then use `Printing.sharePdf` / `Printing.layoutPdf`. Slips of paid months never change.

## get_timeline
The last days as a timeline: scan times, missed visits (gaps), holidays and leave. Used for the "This week" timeline on Home and on the scan result screen.

**Input:** `{ device_id, from: "YYYY-MM-DD", to: "YYYY-MM-DD" }` (at most 31 days, and may span two months)

**Returns:**
```json
{
  "from": "2026-09-23", "to": "2026-09-29", "today": "2026-09-29", "now": "2026-09-29T04:10:00.000Z",
  "windows": { "morning_start": "06:00:00", "morning_end": "12:00:00", "evening_start": "15:00:00", "evening_end": "21:00:00" },
  "done": 9, "missed": 2,
  "days": [ {
    "date": "2026-09-29", "dow": 2, "status": "yellow", "amount": 100,
    "slots": {
      "morning": { "state": "done", "amount": 100, "scanned_at": "2026-09-29T02:12:00Z", "is_offline": false, "is_manual": false },
      "evening": { "state": "pending", "amount": 0, "scanned_at": null, "is_offline": false, "is_manual": false }
    }
  } ]
}
```
`state` takes the same values as in `get_month_summary`.

## update_device
Send this when the FCM token refreshes or she switches language.

**Input:** `{ device_id, fcm_token?, lang?: "en" | "kn" }`

**Returns:** `{ role: "maid", house_name, name }`

---

## Push notifications she receives

Each one arrives in her chosen language.

| When | `data.kind` |
|---|---|
| 30 minutes before a slot closes (11:30 AM / 8:30 PM) with no scan yet, and the slot isn't a holiday or leave | `reminder` |
| Leave approved (paid or unpaid) or rejected | `leave` |
| Holiday added or cancelled by the owner | `holiday` |
| Menu added or changed for today or tomorrow | `menu` |
| Salary marked as paid | `paid` |
