-- Kannada copies of the text the owner and the family type, for the Maid app
-- in Kannada. The Edge Functions fill them when the text is saved; null means
-- "not translated" and the app shows the English.
alter table public.dishes add column name_kn text, add column notes_kn text;
alter table public.menu add column notes_kn text;
alter table public.holidays add column note_kn text;
alter table public.meal_bookings add column note_kn text;
alter table public.members add column name_kn text;

-- English → Kannada, so the same text ("no onion") is translated once.
-- manual = the owner corrected it; later saves of that text reuse the correction.
create table public.translations (
  en text primary key,
  kn text not null,
  manual boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.translations enable row level security;
revoke all on public.translations from anon, authenticated;
