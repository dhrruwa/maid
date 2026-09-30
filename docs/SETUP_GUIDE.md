# Setup guide (beginner-friendly)

This repo has three parts:

| Folder | What it is |
|---|---|
| `supabase/` | The backend: database tables, history triggers, security rules, and the Edge Functions |
| `owner_app/` | **Owner**, the owner's app (Android + iPhone) |
| `maid_app/` | **Maid**, the cook's app (Android + iPhone) |

Docs: `docs/API.md` (Edge Functions the maid app uses) and `docs/mobbin_references.md` (the UI reference for each screen).

> **Already done for you:** the Supabase project `sbyespnawbknbnlbrmht` has every table, trigger and security rule, and all 34 Edge Functions are deployed and tested.
> **You still need to do:** step 3 (cron secret), step 4 (scheduled reminders), step 5 (Firebase) and step 6 (paste the keys into the apps). Steps 1–2 are only for setting up a brand-new Supabase project.

---

## 1. Create a Supabase project (only if starting fresh)
1. Go to <https://supabase.com> → **New project**. Choose Mumbai (ap-south-1): the database and the functions must be close to the phones — this project runs there.
2. Open **SQL Editor → New query**, paste the whole of `supabase/migrations/20260929000000_init.sql`, and press **Run**.
   This creates all tables, the activity-log triggers (history is append-only and nothing is ever hard-deleted), row-level security, and the private `slips` storage bucket.

## 2. Deploy the Edge Functions (only if starting fresh, or after changing them)
You need Node.js installed.
```bash
cd maid                      # this repo
npx supabase login           # opens the browser once
npx supabase functions deploy --project-ref YOUR_PROJECT_REF --use-api
```
`supabase/config.toml` turns off Supabase's JWT check for these functions, because each function checks the phone's device ID itself.

## 3. Set the secrets
Supabase dashboard → **Edge Functions → Secrets** → add:

| Name | Value |
|---|---|
| `CRON_SECRET` | any long random text, e.g. from `openssl rand -hex 24`. It protects the scheduled functions. |
| `FIREBASE_SERVICE_ACCOUNT` | the **whole JSON file** from Firebase (step 5.4). Until this is set, the app works without push notifications. |
| `GEMINI_API_KEY` | optional: a Gemini API key from [Google AI Studio](https://aistudio.google.com/apikey). It translates dish names and notes into Kannada for the Maid app. Without it a free Google web translator is used, which is worse with dish names ("Set Dosa" becomes "set the dosa"). |

(Command-line alternative: `npx supabase secrets set CRON_SECRET=... --project-ref YOUR_PROJECT_REF`.)

## 4. Turn on the scheduled reminders
1. Open `supabase/cron.sql`.
2. Replace `YOUR_PROJECT_REF` (for example `sbyespnawbknbnlbrmht`) and `YOUR_CRON_SECRET` (the same value as in step 3).
3. Paste the file into **SQL Editor** and press **Run**.

This schedules:
- **maid_reminder** every 30 minutes. It reminds the cook at 11:30 AM and 8:30 PM if she hasn't scanned and the slot isn't a holiday or leave.
- **payday_reminder** every day at 9 AM IST. On the 1st it sends "Salary due today", and on the 4th a reminder if you haven't marked it paid.

## 5. Firebase (push notifications)
1. Go to <https://console.firebase.google.com> → **Add project** (Google Analytics can stay off).
2. **Add app → Android** twice:
   - package name `com.cookapp.cook_dashboard` (owner app)
   - package name `com.cookapp.cook_attendance` (maid app)

   You can skip downloading `google-services.json`; the apps read the values from `lib/config.dart` instead.
3. For each Android app, open **Project settings → General → Your apps** and copy:
   - **API key** (`current_key` in google-services.json)
   - **App ID** (`mobilesdk_app_id`, looks like `1:1234567890:android:abc…`)
   - **Project number** (the "Sender ID")
   - **Project ID**
4. **Project settings → Service accounts → Generate new private key**. A JSON file downloads. Paste its **entire content** as the `FIREBASE_SERVICE_ACCOUNT` secret (step 3).
5. **iPhone (owner app only):**
   - **Add app → iOS** with bundle ID `com.dhrruwa.cookdashboard`, and copy its App ID.
   - In **Project settings → Cloud Messaging**, upload an **APNs Authentication Key** (Apple Developer → Keys → "+" → Apple Push Notifications service).
   - In Xcode (`owner_app/ios/Runner.xcworkspace`) → Runner → **Signing & Capabilities → + Capability → Push Notifications**.

## 6. Put the keys into the apps
**Recommended:** keep the keys out of git. Create `dart_defines.json` in the repo root (it is git-ignored):
```json
{
  "SUPABASE_URL": "https://YOUR_PROJECT_REF.supabase.co",
  "SUPABASE_ANON_KEY": "eyJ...",
  "FIREBASE_API_KEY": "AIza...",
  "FIREBASE_IOS_API_KEY": "AIza...",
  "FIREBASE_SENDER_ID": "123456789",
  "FIREBASE_PROJECT_ID": "my-project",
  "FIREBASE_APP_ID_OWNER": "1:123:android:...",
  "FIREBASE_IOS_APP_ID_OWNER": "1:123:ios:...",
  "FIREBASE_APP_ID_MAID": "1:123:android:...",
  "FIREBASE_IOS_APP_ID_MAID": "1:123:ios:..."
}
```
Then add `--dart-define-from-file=../dart_defines.json` to every build command below, for example `flutter build apk --release --dart-define-from-file=../dart_defines.json`.
One file serves both apps: each reads its own `…_OWNER` / `…_MAID` App IDs. Firebase gives iOS apps a separate API key (`API_KEY` in GoogleService-Info.plist), hence `FIREBASE_IOS_API_KEY`.

**iPhone push signing (Owner app):** the Runner target signs manually with the development profile **"Owner Development (push)"** (explicit App ID `com.dhrruwa.cookdashboard` with Push Notifications on). A wildcard team profile can't carry push. When you add a new iPhone, regenerate that profile in Apple Developer → Profiles with the device ticked, or sign in to Xcode and switch the target back to automatic signing.

**Or** edit the default values directly in **both** `owner_app/lib/config.dart` and `maid_app/lib/config.dart`. Don't do this if your repo is public:

```dart
static const supabaseUrl = ... defaultValue: 'https://YOUR_PROJECT_REF.supabase.co'
static const supabaseAnonKey = ... defaultValue: 'eyJ...'      // Supabase → Project Settings → API Keys → anon / publishable
static const firebaseApiKey = ... defaultValue: 'AIza...'
static const firebaseAppId = ... defaultValue: '1:123:android:...'   // the app's own Android App ID
static const firebaseSenderId = ... defaultValue: '123456789'
static const firebaseProjectId = ... defaultValue: 'my-project'
static const firebaseIosAppId = ... defaultValue: '1:123:ios:...'    // owner app only, for iPhone
```
The anon/publishable key is meant to be inside apps. **Never** put the `service_role` key in an app.

If the anon key is left as `PASTE_YOUR_SUPABASE_ANON_KEY_HERE`, the apps still work: they call the Edge Functions directly, because every function checks the phone's device ID itself. Adding the key is still recommended, so calls go through the official `supabase_flutter` client.

## 7. Build the Android apps (APK)
1. Install Flutter: <https://docs.flutter.dev/get-started/install> (Android Studio gives you the Android SDK).
2. Build each app:
   ```bash
   cd owner_app && flutter build apk --release
   cd ../maid_app && flutter build apk --release
   ```
3. Each APK is at `build/app/outputs/flutter-apk/app-release.apk`.

## 8. Install on the phones
**Android:** send the APK to the phone (WhatsApp to yourself, Google Drive, or a USB cable) and tap it. Allow **"Install unknown apps"** when Android asks. Install the owner app on your phone and the maid app on the cook's phone.

**iPhone (either app):** connect the iPhone by cable (or the same Wi-Fi with Developer Mode on), then run:
```bash
cd owner_app                     # or maid_app
flutter build ios --release
xcrun devicectl device install app --device <iPhone UDID> build/ios/iphoneos/Runner.app
# (or: flutter install --release, or open ios/Runner.xcworkspace in Xcode and press ▶)
```
Bundle IDs are `com.dhrruwa.cookdashboard` and `com.dhrruwa.cookattendance`, signed with team `T62SGQ3LT5`. To use a different Apple team, change it in Xcode → Runner → Signing & Capabilities.
The first time, on the iPhone: **Settings → Privacy & Security → Developer Mode → On**, then **Settings → General → VPN & Device Management → trust your developer certificate**.

## 9. First use
**Owner app**
1. Create a 4-digit PIN.
2. Standing in your house, tap **"I'm at home – set location"** (the default allowed distance is 100 m).
3. **Write down the recovery key** it shows. You need it to move the owner app to a new phone.
4. **Print or share the house QR** and stick it in the kitchen.
5. **Pair maid phone**: a QR and a 6-digit code appear, valid for 10 minutes.

**Maid app**
1. Tap **ಕನ್ನಡ / English** at the top to choose the language.
2. Type her name → **Scan pairing QR** (point it at the owner's phone), or **Enter code instead**.
3. From then on she opens the app and taps the big **Scan QR** button at every visit.

## 10. Troubleshooting
| Problem | Fix |
|---|---|
| "You are not at the house" though she is | Settings → **Allowed distance**: raise it to 150–200 m. Check the house location was set from inside the house. |
| No notifications | Check the Firebase values in `config.dart`, the `FIREBASE_SERVICE_ACCOUNT` secret, and that notifications are allowed for the app on the phone. |
| Reminders never come | Steps 3 and 4 (`CRON_SECRET` must match in both places). |
| Cook changed phone | Owner app → Settings → **Pair a new phone**. The old phone stops working automatically. |
| Owner changed phone | Install the owner app → **"Moving from an old phone? Use recovery key"**. |
| Printed QR lost or leaked | Settings → **Regenerate QR**, then print the new one. The old one stops working. |

## 11. How the data is protected
- The apps only hold the public anon key. Row-level security blocks every direct table read and write.
- Every read and write goes through an Edge Function that checks the owner phone's ID or the paired maid phone's ID. The maid phone can only reach her own attendance, menu, leave, salary and slips.
- Nothing is ever hard-deleted: deletes set `deleted_at`, and triggers block real `DELETE`s.
- Every change is written to `activity_log` by triggers: who did it, old value, new value and time. That table can't be updated or deleted.
- Paid months are frozen snapshots, so old slips never change when rates change.

## Changing the app icons
The logos are SVG files in `branding/`: the owner's is a saffron pot with steam rising as bars, and the maid's is a white pot with a green tick. After editing them, render the PNGs into each app's `assets/icon/` folder (`icon.png`, `icon_bg.png`, `icon_fg.png`, `icon_mono.png`, `logo.png`, `splash.png`, `splash_android12.png`), then run this in each app folder:
```bash
dart run flutter_launcher_icons            # every iPhone and Android icon size
dart run flutter_native_splash:create      # launch screen
```

## Appendix: remove the test house created during setup
While building this, an end-to-end test created a house called **"E2E Home"** in your database. It is completely separate from your real house and harmless. If you want it gone, run this in the SQL Editor. It briefly turns off the no-delete protections, only for that house:

```sql
begin;
do $$
declare t text; h uuid;
begin
  select id into h from house where name = 'E2E Home' and owner_device_id like 'e2e-%';
  if h is null then raise notice 'test house not found'; return; end if;
  foreach t in array array['activity_log','menu','dishes','attendance','holidays','leave_requests','payments',
    'monthly_snapshots','cook_device','pairing_tokens','settings','sent_reminders','house'] loop
    execute format('alter table %I disable trigger user', t);
  end loop;
  foreach t in array array['menu','dishes','attendance','holidays','leave_requests','payments',
    'monthly_snapshots','cook_device','pairing_tokens','settings','sent_reminders'] loop
    execute format('delete from %I where house_id = %L', t, h);
  end loop;
  delete from house where id = h;
  delete from activity_log where house_id = h;
  foreach t in array array['activity_log','menu','dishes','attendance','holidays','leave_requests','payments',
    'monthly_snapshots','cook_device','pairing_tokens','settings','sent_reminders','house'] loop
    execute format('alter table %I enable trigger user', t);
  end loop;
end $$;
commit;
```
Its two test slip PDFs are in **Storage → slips → 9068a525-…/**. Delete that folder there if you like.
