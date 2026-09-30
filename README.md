# Owner + Maid: home cook attendance

<p>
  <img src="branding/owner-rounded.svg" width="96" alt="Owner app logo">
  &nbsp;
  <img src="branding/maid-rounded.png" width="96" alt="Maid logo">
</p>

Two Flutter apps and a Supabase backend for tracking a home cook's attendance, salary, holidays, leave and daily menu.

| Part | Folder | Platform |
|---|---|---|
| Owner app – **Owner** | `owner_app/` | Android, iPhone |
| Maid app – **Maid** (English + ಕನ್ನಡ) | `maid_app/` | Android, iPhone |
| Backend – Postgres schema, triggers, RLS, 40 Edge Functions, cron | `supabase/` | Supabase |

- **Setup, build and install steps:** [docs/SETUP_GUIDE.md](docs/SETUP_GUIDE.md)
- **Edge Function API (maid app):** [docs/API.md](docs/API.md)
- **Mobbin UI references:** [docs/mobbin_references.md](docs/mobbin_references.md)
- **Maid app over-the-air updates (Shorebird):** [docs/OTA.md](docs/OTA.md)
- **Maid app server-driven Home (layout, notices, wording from the database):** [docs/SDUI.md](docs/SDUI.md)
- **Colours and glass style:** [docs/COLOR_PALETTE.md](docs/COLOR_PALETTE.md)
- **Logos and icons:** `branding/` (SVG sources); generated into each app's `assets/icon/`
- **Original build prompts:** `owner_app_prompt_4.md`, `maid_app_prompt_4.md`

## Rules in short
- Morning 6 AM–12 PM every day; evening 3 PM–9 PM Monday–Friday. One scan per slot. All times are Asia/Kolkata.
- ₹100 per weekday visit, ₹200 per weekend visit (morning only). Paid holidays and paid leave count in full. Rates and windows are editable.
- Salary cycle runs from the 1st to the last day of the month and is paid on the 1st. Paid months are frozen.
- Scans must be at the house (GPS radius, mocked GPS rejected), from the paired phone, with the current house QR. Offline scans are accepted if uploaded within 12 hours.
- Nothing is ever hard-deleted, and every change is recorded in an append-only activity log.
