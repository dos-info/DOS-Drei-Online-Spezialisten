-- Run once in Supabase SQL Editor.
create table if not exists public.employee_work_sessions (
  id uuid primary key default gen_random_uuid(),
  employee_profile_id uuid not null references public.profiles(id) on delete cascade,
  work_date date not null default current_date,
  started_at timestamptz,
  ended_at timestamptz,
  break_minutes integer not null default 0 check (break_minutes >= 0),
  status text not null default 'offline' check (status in ('working', 'break', 'offline', 'leave', 'sick', 'vacation', 'training', 'meeting', 'call', 'lunch')),
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.employee_work_sessions drop constraint if exists employee_work_sessions_status_check;
alter table public.employee_work_sessions add constraint employee_work_sessions_status_check
  check (status in ('working', 'break', 'offline', 'leave', 'sick', 'vacation', 'training', 'meeting', 'call', 'lunch'));

create index if not exists employee_work_sessions_employee_idx on public.employee_work_sessions(employee_profile_id, work_date desc);
alter table public.employee_work_sessions enable row level security;

drop policy if exists "Employees view own work sessions" on public.employee_work_sessions;
create policy "Employees view own work sessions" on public.employee_work_sessions for select to authenticated
  using (employee_profile_id = auth.uid());
drop policy if exists "Employees manage own work sessions" on public.employee_work_sessions;
create policy "Employees manage own work sessions" on public.employee_work_sessions for insert to authenticated
  with check (employee_profile_id = auth.uid() and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('accountant', 'staff')));
drop policy if exists "Employees update own work sessions" on public.employee_work_sessions;
create policy "Employees update own work sessions" on public.employee_work_sessions for update to authenticated
  using (employee_profile_id = auth.uid()) with check (employee_profile_id = auth.uid());
drop policy if exists "Admins view all work sessions" on public.employee_work_sessions;
create policy "Admins view all work sessions" on public.employee_work_sessions for select to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));
drop policy if exists "Admins manage all work sessions" on public.employee_work_sessions;
create policy "Admins manage all work sessions" on public.employee_work_sessions for update to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'employee_work_sessions') then
    alter publication supabase_realtime add table public.employee_work_sessions;
  end if;
end $$;