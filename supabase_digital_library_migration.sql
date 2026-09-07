-- Run once in Supabase SQL Editor.
insert into storage.buckets (id, name, public)
values ('course-library', 'course-library', false)
on conflict (id) do update set public = false;

alter table public.course_library add column if not exists library_type text not null default 'digital';
alter table public.course_library add column if not exists storage_path text;
update public.course_library
set storage_path = split_part(url, '/object/public/course-library/', 2), url = ''
where coalesce(storage_path, '') = '' and url like '%/object/public/course-library/%';

drop policy if exists "Library files can be uploaded by staff" on storage.objects;
create policy "Library files can be uploaded by staff" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'course-library'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('admin', 'instructor'))
  );

drop policy if exists "Admins can add library records" on public.course_library;
create policy "Admins can add library records" on public.course_library
  for insert to authenticated
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

drop policy if exists "Admins can update library records" on public.course_library;
create policy "Admins can update library records" on public.course_library
  for update to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

drop policy if exists "Admins can delete library records" on public.course_library;
create policy "Admins can delete library records" on public.course_library
  for delete to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

drop policy if exists "Library files are publicly readable" on storage.objects;
drop policy if exists "Library files are readable by authenticated users" on storage.objects;
drop policy if exists "Authorized users can read library files" on storage.objects;
create policy "Authorized users can read library files" on storage.objects
  for select to public
  using (
    bucket_id = 'course-library'
    and auth.role() = 'authenticated'
    and (
      exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('admin', 'instructor'))
      or exists (select 1 from public.course_library c join public.students s on s.profile_id = auth.uid() where c.storage_path = name and c.visible = true and s.library_access_enabled = true)
    )
  );

drop policy if exists "Library files can be deleted by staff" on storage.objects;
create policy "Library files can be deleted by staff" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'course-library'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('admin', 'instructor'))
  );

alter table public.course_library drop constraint if exists course_library_library_type_check;
alter table public.course_library add constraint course_library_library_type_check check (library_type in ('paper', 'digital'));

alter table public.course_library enable row level security;
drop policy if exists "Authenticated users can view course library" on public.course_library;
create policy "Authorized users can view course library" on public.course_library
  for select to authenticated
  using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('admin', 'instructor'))
    or (visible = true and exists (select 1 from public.students s where s.profile_id = auth.uid() and s.library_access_enabled = true))
  );
drop policy if exists "Instructors can add course library files" on public.course_library;
create policy "Instructors can add course library files" on public.course_library
  for insert to authenticated
  with check (
    instructor_profile_id = auth.uid()
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'instructor')
  );
drop policy if exists "Instructors can update course library files" on public.course_library;
create policy "Instructors can update course library files" on public.course_library
  for update to authenticated
  using (instructor_profile_id = auth.uid())
  with check (instructor_profile_id = auth.uid());
drop policy if exists "Instructors can delete course library files" on public.course_library;
create policy "Instructors can delete course library files" on public.course_library
  for delete to authenticated
  using (instructor_profile_id = auth.uid());
