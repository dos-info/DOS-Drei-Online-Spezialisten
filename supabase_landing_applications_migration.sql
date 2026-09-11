-- Run once in Supabase SQL Editor.
-- Public course reservation applications. Personal data is readable only by authorized staff.
create table if not exists public.landing_applications (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text not null,
  phone text not null,
  qualification text not null default '',
  governorate text not null default '',
  course text not null,
  status text not null default 'pending' check (status in ('pending', 'contacted', 'approved', 'rejected')),
  admin_note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.landing_applications enable row level security;

-- Keep the newest record before enforcing one application per email.
delete from public.landing_applications older
using public.landing_applications newer
where lower(trim(older.email)) = lower(trim(newer.email))
  and (older.created_at < newer.created_at or (older.created_at = newer.created_at and older.id < newer.id));

create unique index if not exists landing_applications_email_unique_idx
  on public.landing_applications (lower(trim(email)));

drop policy if exists "Public visitors can submit landing applications" on public.landing_applications;
create policy "Public visitors can submit landing applications"
on public.landing_applications for insert to anon, authenticated
with check (length(trim(full_name)) between 2 and 120 and length(trim(email)) between 5 and 180 and length(trim(phone)) between 5 and 40 and length(trim(course)) between 2 and 100);

drop policy if exists "Authorized staff can view landing applications" on public.landing_applications;
create policy "Authorized staff can view landing applications"
on public.landing_applications for select to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and (p.role = 'admin' or coalesce(p.permissions, '[]'::jsonb) ? 'view_landing_applications')
  )
);

drop policy if exists "Authorized staff can manage landing applications" on public.landing_applications;
create policy "Authorized staff can manage landing applications"
on public.landing_applications for update to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and (p.role = 'admin' or coalesce(p.permissions, '[]'::jsonb) ? 'manage_landing_applications')
  )
)
with check (true);

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'landing_applications'
  ) then
    alter publication supabase_realtime add table public.landing_applications;
  end if;
end $$;
