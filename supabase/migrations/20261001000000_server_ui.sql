-- Server-driven UI (SDUI) for the Maid app
-- A row is one UI bundle: the blocks each screen shows, in order, plus text
-- overrides for the app's own strings. See docs/SDUI.md for the block types.
--
-- The app ships a built-in bundle (maid_app/assets/ui/default.json). With no
-- active row here it keeps using that, so this table starts empty.
-- The newest active row for the house wins; otherwise the newest global row
-- (house_id null). A row is only sent to apps whose block schema is at least
-- `schema`, so a bundle using newer blocks never reaches an older app.
-- Rows are never deleted: switch one off with active = false, or add a newer one.

create table public.app_ui (
  id uuid primary key default gen_random_uuid(),
  app text not null default 'maid' check (app in ('maid')),
  house_id uuid references public.house(id),
  schema integer not null default 1 check (schema >= 1),
  screens jsonb not null default '{}'::jsonb check (jsonb_typeof(screens) = 'object'),
  strings jsonb not null default '{}'::jsonb check (jsonb_typeof(strings) = 'object'),
  note text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index app_ui_lookup_idx on public.app_ui (app, house_id, created_at desc) where active;

-- Only the Edge Functions (service role) touch it.
alter table public.app_ui enable row level security;
revoke all on public.app_ui from anon, authenticated;
