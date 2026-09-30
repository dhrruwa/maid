# Server-driven UI (Maid app)

The Maid app's **Home screen** is a list of blocks. The list can come from the database, so you can change what the cook sees without a new build and without an update:

- show a notice ("Diwali: paid holiday 20–22 Oct"), which can switch itself off after a date
- change the order of the cards, or hide one
- add a button (call the owner, open WhatsApp, open a video)
- change or fix any of the app's own wording, in English and Kannada

For changes to the code itself (new screens, new block types, bug fixes), use OTA patches instead: see [OTA.md](OTA.md).

## How it works

```
app start ──► saved layout (or the built-in one) is shown at once
Home loads ─► get_ui ──► newest active row in public.app_ui ──► saved + shown
```

- **Built-in layout:** [`maid_app/lib/sdui/default_ui.dart`](../maid_app/lib/sdui/default_ui.dart). It is used on first start, when there is no row in `app_ui`, and when a row is unusable.
- **Server layout:** the newest active row in `public.app_ui` for the house, otherwise the newest global row (`house_id` null). The function is [`get_ui`](API.md#get_ui).
- **Saved:** the last layout the phone received is kept, so Home looks the same offline. A new layout shows the next time Home loads. That happens on opening the app, on pull-to-refresh, after a scan, or on any push notification.
- **Safety:**
  - If the server's Home has no `scan_button`, the phone ignores it and uses the built-in layout, so the cook can always scan.
  - Unknown block types, blocks with bad values, and blocks outside their dates are left out. The rest of the screen still shows.

## Change the layout

Run SQL in the Supabase SQL editor (project **maid-mumbai**). Rows are never deleted. To change something, add a new row. To go back, switch the new row off.

```sql
-- A new Home for every house. The newest active row wins.
insert into public.app_ui (note, screens) values (
  'Diwali notice on top',
  '{
    "home": { "blocks": [
      { "type": "notice", "icon": "celebration", "tone": "success",
        "title": { "en": "Happy Diwali, {name}!", "kn": "ದೀಪಾವಳಿ ಶುಭಾಶಯಗಳು, {name}!" },
        "text":  { "en": "20–22 Oct are paid holidays.", "kn": "ಅಕ್ಟೋಬರ್ 20–22 ಸಂಬಳ ಸಹಿತ ರಜೆ." },
        "until": "2026-10-22" },
      { "type": "offline_banner" },
      { "type": "saved_banner" },
      { "type": "salary_card" },
      { "type": "today_card" },
      { "type": "scan_button" },
      { "type": "cook_card" },
      { "type": "week_timeline" },
      { "type": "more_buttons" },
      { "type": "app_version" }
    ] }
  }'
);

-- Only for one house: add  house_id  (select id, name from public.house;)
-- insert into public.app_ui (house_id, note, screens) values ('<house id>', '…', '{…}');

-- Undo: switch the newest row off (the one before it, or the built-in layout, comes back).
update public.app_ui set active = false
where id = (select id from public.app_ui where active order by created_at desc limit 1);

-- What is live:
select id, house_id, schema, note, active, created_at from public.app_ui order by created_at desc;
```

## Change the app's wording

`strings` overrides any key in [`maid_app/assets/i18n/en.json`](../maid_app/assets/i18n/en.json) and `kn.json`. The keys and `{placeholders}` must match those files. A key you leave out keeps the built-in text. If you give only English, Kannada still uses the built-in Kannada.

```sql
insert into public.app_ui (note, strings) values (
  'Clearer scan button',
  '{ "en": { "scan_qr": "Scan kitchen QR" },
     "kn": { "scan_qr": "ಅಡುಗೆಮನೆ QR ಸ್ಕ್ಯಾನ್ ಮಾಡಿ" } }'
);
```

A row can have both `screens` and `strings`. Only one row is live at a time, so put everything you want in the newest row. A row with only `strings` gives the built-in Home.

## Blocks

Every block is `{ "type": "…", …props }`. Props you can use on any block:

| Prop | Example | Meaning |
|---|---|---|
| `from` | `"2026-10-20"` or `"2026-10-20T18:00:00+05:30"` | show from this India date, or from this exact time |
| `until` | `"2026-10-22"` | show until the end of this India date, or until this exact time |
| `hidden` | `true` | switched off, but kept in the list |

### Home's own blocks

| Type | Shows | Props |
|---|---|---|
| `offline_banner` | "N scans waiting to upload" (only when there are some) | |
| `saved_banner` | "Showing saved information" (only when offline) | |
| `salary_card` | Earned so far, progress, payday | |
| `today_card` | Morning / Evening status today | |
| `scan_button` | The big Scan QR button. **Required.** | `label` (text), `height` (64–140, default 92) |
| `cook_card` | What to cook, Today / Tomorrow, who's eating | |
| `week_timeline` | This week's visits | |
| `more_buttons` | Request leave · My history | |

### General blocks

| Type | Props |
|---|---|
| `notice` | `title`, `text` (at least one), `icon`, `tone`, `action` (tap) |
| `text` | `text`, `size` (13–40, default 17), `bold`, `muted`, `align` (`start` / `center` / `end`) |
| `button` | `label`, `action` (both required), `icon`, `style` (`filled` or outlined), `height` (56–120) |
| `image` | `url` (https only), `height` (60–400, default 170), `alt`, `action`. Left out when offline. |
| `video` | `url` (YouTube), `title`. Plays in the app, with "Open in YouTube". |
| `card` | `title`, `icon`, `children` (blocks) |
| `row` | `children` (blocks), side by side, one under the other on narrow phones |
| `spacer` | `height` (0–120) |
| `app_version` | Small "Maid 0.1.0 (1) · patch 3" line. Use it to check that a phone got an OTA patch. |

**Text** (`title`, `text`, `label`, `alt`) can be:
- `"Plain text"`
- `{ "en": "…", "kn": "…" }`: in the cook's language, falling back to English
- `{ "key": "scan_qr" }`: one of the app's own strings

`{name}` becomes the cook's name.

**Actions:**
- `"scan"`, `"leave"`, `"history"`, `"refresh"`
- a link:
  - `"tel:+91…"` to call
  - `"https://wa.me/91…"` for WhatsApp
  - `"https://…"`

Any other action makes a `button` disappear. On a `notice` or `image`, it just isn't tappable.

**Tones:** `success` (green), `warning` (amber), `danger` (red), `info` (blue), `neutral` (grey), `brand` (saffron, the default).

**Icons:** `info` `campaign` `celebration` `gift` `star` `favorite` `warning` `check` `cancel` `help` `event` `calendar` `schedule` `sun` `moon` `restaurant` `people` `wallet` `payments` `holiday` `leave` `history` `qr` `phone` `chat` `video` `link` `refresh` `location` `notifications` `home`. Flutter only ships the icons the code names, so a new icon needs a code change (an OTA patch is enough).

## Adding a new block type (developers)

1. Build it in `UiRenderer` ([`blocks.dart`](../maid_app/lib/sdui/blocks.dart)) if it works on any screen. If it belongs to Home, add it to Home's `_renderer` map ([`home_screen.dart`](../maid_app/lib/screens/home_screen.dart)).
2. Raise `ServerUi.schema` ([`server_ui.dart`](../maid_app/lib/sdui/server_ui.dart)) by one.
3. Ship it: an OTA patch (`shorebird patch android`) is enough, unless the block needs a new plugin.
4. Give rows that use the new block the new schema: `insert into public.app_ui (schema, …) values (2, …)`. `get_ui` only sends a row to apps whose schema is at least the row's, so phones that don't have the patch yet keep their current layout.

Tests: `cd maid_app && flutter test test/sdui_test.dart`.
