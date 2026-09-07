-- Run once in Supabase SQL Editor.
alter table public.profiles add column if not exists permissions jsonb not null default '[]'::jsonb;
alter table public.profiles add column if not exists job_title text not null default '';

create or replace function public.is_current_user_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

revoke all on function public.is_current_user_admin() from public;
grant execute on function public.is_current_user_admin() to authenticated;

drop policy if exists "Admins update employee permissions" on public.profiles;
create policy "Admins update employee permissions" on public.profiles for update to authenticated
  using (public.is_current_user_admin())
  with check (public.is_current_user_admin());

update public.profiles set permissions = case role
  when 'admin' then '["manage_students","create_students","edit_students","view_finance","manage_finance","view_work_hours","edit_work_hours","manage_library","view_library","manage_instructors","view_activity_log","return_to_employee_management"]'::jsonb
  when 'accountant' then '["create_students","edit_students","view_finance","manage_finance","view_work_hours","view_library","return_to_employee_management"]'::jsonb
  when 'staff' then '["view_work_hours","return_to_employee_management"]'::jsonb
  when 'instructor' then '["view_work_hours","edit_work_hours","view_library"]'::jsonb
  else permissions
end
where permissions = '[]'::jsonb;

update public.employee_work_sessions set status = 'working' where status = 'working';
update public.employee_work_sessions set status = 'break' where status = 'break';
update public.employee_work_sessions set status = 'offline' where status in ('leave', 'sick', 'vacation', 'call');

alter table public.employee_work_sessions drop constraint if exists employee_work_sessions_status_check;
alter table public.employee_work_sessions add constraint employee_work_sessions_status_check
  check (status in ('working', 'lecture', 'break', 'lunch', 'meeting', 'technical_error', 'offline', 'training', 'personal', 'shadowing'));

drop policy if exists "Employees manage own work sessions" on public.employee_work_sessions;
create policy "Employees manage own work sessions" on public.employee_work_sessions for insert to authenticated
  with check (employee_profile_id = auth.uid() and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('accountant', 'staff', 'instructor')));
