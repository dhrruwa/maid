-- Cook Dashboard / Cook Attendance – full schema
-- Run once in the Supabase SQL editor (or `supabase db push`).

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Keeps updated_at fresh on every update.
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- Who is making the change. Edge Functions send an `x-actor` header
-- (owner / maid / system); PostgREST exposes request headers as a setting.
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
  if hdr in ('owner', 'maid', 'system') then
    return hdr;
  end if;
  return 'system';
end $$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.house (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'Home',
  lat double precision,
  lng double precision,
  radius_m integer not null default 100,
  qr_token text not null default encode(extensions.gen_random_bytes(24), 'hex'),
  owner_pin_hash text,
  owner_device_id text not null unique,
  owner_fcm_token text,
  recovery_key_hash text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.pairing_tokens (
  token text primary key,
  code_6digit text not null,
  house_id uuid not null references public.house(id),
  expires_at timestamptz not null,
  used boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index pairing_tokens_code_idx on public.pairing_tokens (code_6digit) where not used;

create table public.cook_device (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.house(id),
  device_id text not null,
  name text not null,
  fcm_token text,
  lang text not null default 'en' check (lang in ('en', 'kn')),
  paired_at timestamptz not null default now(),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index cook_device_device_idx on public.cook_device (device_id) where active;

create table public.settings (
  house_id uuid primary key references public.house(id),
  weekday_rate integer not null default 100,
  weekend_rate integer not null default 200,
  morning_start time not null default '06:00',
  morning_end time not null default '12:00',
  evening_start time not null default '15:00',
  evening_end time not null default '21:00',
  notify_scan boolean not null default true,
  notify_leave boolean not null default true,
  notify_offline boolean not null default true,
  notify_payday boolean not null default true,
  notify_menu boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.attendance (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.house(id),
  device_id text,
  date date not null,
  slot text not null check (slot in ('morning', 'evening')),
  scanned_at timestamptz not null,
  uploaded_at timestamptz not null default now(),
  lat double precision,
  lng double precision,
  distance_m integer,
  amount integer not null default 0,
  is_offline boolean not null default false,
  is_manual boolean not null default false,
  note text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index attendance_one_per_slot
  on public.attendance (house_id, date, slot) where deleted_at is null;

create table public.holidays (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.house(id),
  date date not null,
  slot text not null check (slot in ('morning', 'evening', 'full')),
  paid boolean not null default true,
  note text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index holidays_house_date_idx on public.holidays (house_id, date) where deleted_at is null;

create table public.leave_requests (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.house(id),
  device_id text,
  date date not null,
  slot text not null check (slot in ('morning', 'evening', 'full')),
  reason text,
  status text not null default 'pending'
    check (status in ('pending', 'approved_paid', 'approved_unpaid', 'rejected')),
  decided_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index leave_house_date_idx on public.leave_requests (house_id, date) where deleted_at is null;

create table public.dishes (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.house(id),
  name text not null,
  youtube_url text,
  notes text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.menu (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.house(id),
  date date not null,
  slot text not null check (slot in ('morning', 'evening')),
  dish_id uuid not null references public.dishes(id),
  notes text,
  sort_order integer not null default 0,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index menu_house_date_idx on public.menu (house_id, date) where deleted_at is null;

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.house(id),
  month text not null check (month ~ '^\d{4}-\d{2}$'),
  total_amount integer not null,
  paid_on date not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (house_id, month)
);

create table public.monthly_snapshots (
  id uuid primary key default gen_random_uuid(),
  house_id uuid not null references public.house(id),
  month text not null check (month ~ '^\d{4}-\d{2}$'),
  rates_used jsonb not null,
  summary jsonb not null,
  slip_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (house_id, month)
);

-- Stops the scheduled reminders from sending the same message twice.
create table public.sent_reminders (
  house_id uuid not null references public.house(id),
  kind text not null,
  day date not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (house_id, kind, day)
);

create table public.activity_log (
  id bigint generated always as identity primary key,
  house_id uuid,
  actor text not null check (actor in ('owner', 'maid', 'system')),
  action text not null check (action in ('create', 'update', 'delete', 'restore')),
  entity_type text not null,
  entity_id text,
  old_value jsonb,
  new_value jsonb,
  note text,
  created_at timestamptz not null default now()
);
create index activity_house_time_idx on public.activity_log (house_id, created_at desc);

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['house','pairing_tokens','cook_device','settings','attendance',
    'holidays','leave_requests','dishes','menu','payments','monthly_snapshots','sent_reminders']
  loop
    execute format('create trigger %I_touch before update on public.%I
                    for each row execute function public.touch_updated_at()', t, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Activity log triggers
-- ---------------------------------------------------------------------------

-- Secret columns are never copied into the log in clear text.
create or replace function public.mask_secrets(j jsonb) returns jsonb
language sql immutable as $$
  select case when j is null then null else
    (select coalesce(jsonb_object_agg(k,
       case when k in ('owner_pin_hash','qr_token','token','code_6digit','owner_fcm_token',
                       'fcm_token','recovery_key_hash','owner_device_id')
                 and v <> 'null'::jsonb
            -- short fingerprint: shows that a secret changed, never its value
            then to_jsonb('***' || left(md5(v::text), 6)) else v end), '{}'::jsonb)
     from jsonb_each(j) as e(k, v))
  end
$$;

create or replace function public.log_activity() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_action text;
  v_old jsonb;
  v_new jsonb;
  v_house uuid;
  v_id text;
  v_note text;
begin
  if tg_op = 'INSERT' then
    v_action := 'create';
    v_new := to_jsonb(new);
  else
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    -- Nothing that matters changed (only updated_at): skip.
    if (v_old - 'updated_at') = (v_new - 'updated_at') then
      return new;
    end if;
    if v_old ? 'deleted_at' and (v_old->>'deleted_at') is null and (v_new->>'deleted_at') is not null then
      v_action := 'delete';
    elsif v_old ? 'deleted_at' and (v_old->>'deleted_at') is not null and (v_new->>'deleted_at') is null then
      v_action := 'restore';
    else
      v_action := 'update';
    end if;
  end if;

  v_house := coalesce((v_new->>'house_id')::uuid,
                      case when tg_table_name = 'house' then (v_new->>'id')::uuid end);
  v_id := coalesce(v_new->>'id', v_new->>'token', v_new->>'house_id');
  v_note := v_new->>'note';

  insert into public.activity_log (house_id, actor, action, entity_type, entity_id,
                                   old_value, new_value, note)
  values (v_house, public.current_actor(), v_action, tg_table_name, v_id,
          public.mask_secrets(v_old), public.mask_secrets(v_new), v_note);
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['house','pairing_tokens','cook_device','settings','attendance',
    'holidays','leave_requests','dishes','menu','payments','monthly_snapshots']
  loop
    execute format('create trigger %I_log after insert or update on public.%I
                    for each row execute function public.log_activity()', t, t);
  end loop;
end $$;

-- Nothing is ever hard-deleted.
create or replace function public.forbid_delete() returns trigger
language plpgsql as $$
begin
  raise exception 'Rows in % cannot be deleted. Use soft delete (deleted_at).', tg_table_name;
end $$;

do $$
declare t text;
begin
  foreach t in array array['house','pairing_tokens','cook_device','settings','attendance',
    'holidays','leave_requests','dishes','menu','payments','monthly_snapshots','sent_reminders']
  loop
    execute format('create trigger %I_no_delete before delete on public.%I
                    for each row execute function public.forbid_delete()', t, t);
  end loop;
end $$;

-- activity_log is append-only.
create or replace function public.forbid_log_change() returns trigger
language plpgsql as $$
begin
  raise exception 'activity_log is append-only';
end $$;

create trigger activity_log_append_only
  before update or delete on public.activity_log
  for each row execute function public.forbid_log_change();

create trigger activity_log_no_truncate
  before truncate on public.activity_log
  for each statement execute function public.forbid_log_change();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- Apps only hold the anon key. With RLS on and no policies, anon/authenticated
-- clients can neither read nor write any table directly. Every read and write
-- goes through Edge Functions, which use the service role and check the
-- owner device ID or the paired maid device ID themselves.
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['house','pairing_tokens','cook_device','settings','attendance',
    'holidays','leave_requests','dishes','menu','payments','monthly_snapshots',
    'sent_reminders','activity_log']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Storage bucket for payment slips (private; the functions hand out signed URLs)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('slips', 'slips', false)
on conflict (id) do nothing;
