-- Run this script in Supabase SQL Editor once.
-- It adds the instructor payroll, attendance, and scheduling fields used by the app.

alter table public.instructors
  add column if not exists join_date date,
  add column if not exists hours numeric(10, 2) not null default 0,
  add column if not exists hourly_rate numeric(10, 2) not null default 0,
  add column if not exists salary_total numeric(12, 2) not null default 0,
  add column if not exists salary_paid numeric(12, 2) not null default 0,
  add column if not exists payment_date date,
  add column if not exists salary_total_since_start numeric(12, 2) not null default 0,
  add column if not exists other_payment_name text not null default '',
  add column if not exists other_payment_amount numeric(12, 2) not null default 0,
  add column if not exists other_payment_details text not null default '',
  add column if not exists next_payment_date date,
  add column if not exists next_payment_info text not null default '',
  add column if not exists penalties numeric(12, 2) not null default 0,
  add column if not exists absences integer not null default 0;

update public.instructors
set salary_total = coalesce(hours, 0) * coalesce(hourly_rate, 0)
where coalesce(salary_total, 0) = 0
  and (coalesce(hours, 0) > 0 or coalesce(hourly_rate, 0) > 0);

-- The existing v_instructors view must expose the new columns.
-- If the view does not already select them, edit its SELECT list in Supabase
-- to include: join_date, hours, hourly_rate, salary_total, salary_paid,
-- payment_date, salary_total_since_start, other_payment_name,
-- other_payment_amount, other_payment_details, next_payment_date,
-- next_payment_info, penalties, absences.
