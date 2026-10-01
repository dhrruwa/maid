-- What a paid holiday or paid leave pays, per meal (morning or evening).
-- A full-day paid holiday is two meals. Paid months keep their frozen slips.
alter table public.settings
  add column if not exists paid_off_rate integer not null default 35 check (paid_off_rate between 0 and 100000);
