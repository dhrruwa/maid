-- Scheduled functions (pg_cron + pg_net).
-- 1. Replace YOUR_CRON_SECRET below with the same value you saved as the
--    CRON_SECRET Edge Function secret.
-- 2. Replace YOUR_PROJECT_REF with your project ref (e.g. sbyespnawbknbnlbrmht).
-- 3. Run this whole file once in the Supabase SQL editor.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Remove old copies if you run this file again.
select cron.unschedule(jobname) from cron.job where jobname in ('maid_reminder', 'payday_reminder', 'family_notify');

-- Every 30 minutes (UTC :00/:30 = IST :30/:00). The function itself only
-- sends in the 30 minutes before a slot closes (11:30 AM / 8:30 PM IST).
select cron.schedule(
  'maid_reminder',
  '*/30 * * * *',
  $$
  select net.http_post(
    url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/maid_reminder',
    headers := '{"Content-Type": "application/json", "x-cron-secret": "YOUR_CRON_SECRET"}'::jsonb,
    body := '{}'::jsonb
  );
  $$
);

-- Daily at 9:00 AM IST (= 03:30 UTC). Sends on the 1st, and again on the 4th if unpaid.
select cron.schedule(
  'payday_reminder',
  '30 3 * * *',
  $$
  select net.http_post(
    url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/payday_reminder',
    headers := '{"Content-Type": "application/json", "x-cron-secret": "YOUR_CRON_SECRET"}'::jsonb,
    body := '{}'::jsonb
  );
  $$
);

-- Family app: menu-change notices and booking reminders (see family_notify).
select cron.schedule(
  'family_notify',
  '*/10 * * * *',
  $$
  select net.http_post(
    url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/family_notify',
    headers := '{"Content-Type": "application/json", "x-cron-secret": "YOUR_CRON_SECRET"}'::jsonb,
    body := '{}'::jsonb
  );
  $$
);
