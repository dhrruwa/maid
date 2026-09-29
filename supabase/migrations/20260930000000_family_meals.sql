-- Family meal booking
-- Each family member gets a login for the Family app (name + 4-digit PIN).
-- Only a salted SHA-256 of the PIN is stored (never the PIN or a phone number):
--   pin_hash = hex(sha256('member-pin:' || members.id || ':' || pin))
-- The Edge Functions compute it with _shared/http.ts sha256Hex; SQL seeding uses
--   encode(extensions.digest('member-pin:' || id || ':' || pin, 'sha256'), 'hex')
-- Members opt in to meals: one active booking per member, date and slot.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.members (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.house(id),
  name text not null check (btrim(name) <> ''),
  pin_hash text not null check (pin_hash ~ '^[0-9a-f]{64}$'),
  failed_attempts integer not null default 0,
  locked_until timestamptz,
  device_id text,
  fcm_token text,
  linked_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- A name is unique per house (case-insensitive) among active members.
create unique index members_house_name_idx on public.members (house_id, lower(name)) where active;
-- A phone is logged in as at most one member.
create unique index members_device_idx on public.members (device_id) where device_id is not null;

create table public.meal_bookings (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.house(id),
  member_id uuid not null references public.members(id),
  date date not null,
  slot text not null check (slot in ('morning', 'evening')),
  note text,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index meal_bookings_one_active
  on public.meal_bookings (member_id, date, slot) where cancelled_at is null;
create index meal_bookings_house_date_idx
  on public.meal_bookings (house_id, date) where cancelled_at is null;

-- ---------------------------------------------------------------------------
-- Triggers: updated_at, activity log, no hard deletes
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['members', 'meal_bookings']
  loop
    execute format('create trigger %I_touch before update on public.%I
                    for each row execute function public.touch_updated_at()', t, t);
    execute format('create trigger %I_log after insert or update on public.%I
                    for each row execute function public.log_activity()', t, t);
    execute format('create trigger %I_no_delete before delete on public.%I
                    for each row execute function public.forbid_delete()', t, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Activity log: a family member can be the actor
-- ---------------------------------------------------------------------------
alter table public.activity_log drop constraint activity_log_actor_check;
alter table public.activity_log add constraint activity_log_actor_check
  check (actor in ('owner', 'maid', 'member', 'system'));

create or replace function public.current_actor() returns text
language plpgsql stable as $$
declare
  hdr text;
begin
  begin
    hdr := current_setting('request.headers', true)::json ->> 'x-actor';
  exception when others then
    hdr := null;
  end;
  if hdr in ('owner', 'maid', 'member', 'system') then
    return hdr;
  end if;
  return 'system';
end $$;

-- Secrets (now also PIN hashes and device IDs) are never copied into the log
-- in clear text. Each one becomes a short fingerprint that only shows whether
-- it changed between old_value and new_value of the same log row. The
-- fingerprint is keyed with a random value that exists only for the current
-- transaction: an unkeyed md5 of a 4-digit PIN's hash could be matched against
-- all 10,000 PINs by anyone holding the log or a data export.
create or replace function public.mask_secrets(j jsonb) returns jsonb
language plpgsql volatile as $$
declare
  k text := nullif(current_setting('app.log_mask_key', true), '');
begin
  if j is null then
    return null;
  end if;
  if k is null then
    k := set_config('app.log_mask_key', encode(extensions.gen_random_bytes(16), 'hex'), true);
  end if;
  return (select coalesce(jsonb_object_agg(e.key,
       case when e.key in ('owner_pin_hash','qr_token','token','code_6digit','owner_fcm_token',
                           'fcm_token','recovery_key_hash','owner_device_id',
                           'pin_hash','device_id')
                 and e.value <> 'null'::jsonb
            then to_jsonb('***' || left(md5(k || e.value::text), 6)) else e.value end), '{}'::jsonb)
     from jsonb_each(j) as e);
end $$;

-- ---------------------------------------------------------------------------
-- Row Level Security: only the Edge Functions (service role) touch these.
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['members', 'meal_bookings']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;
