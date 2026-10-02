-- Run once in the Supabase SQL Editor after deploying the library-content Edge Function.
-- Files remain in a private bucket and are streamed only after per-request authorization.
begin;

update storage.buckets
set public = false
where id = 'course-library';

alter table public.course_library
  add column if not exists library_type text not null default 'digital',
  add column if not exists storage_path text;

alter table public.course_library
  add column if not exists student_download_enabled boolean not null default true;

update public.course_library
set storage_path = split_part(
  case
    when url like '%/object/public/course-library/%' then split_part(url, '/object/public/course-library/', 2)
    else split_part(url, '/object/sign/course-library/', 2)
  end,
  '?', 1
), url = ''
where coalesce(storage_path, '') = ''
  and (url like '%/object/public/course-library/%' or url like '%/object/sign/course-library/%');

drop policy if exists "Library files are publicly readable" on storage.objects;
drop policy if exists "Library files are readable by authenticated users" on storage.objects;
drop policy if exists "Authorized users can read library files" on storage.objects;
drop policy if exists "Library files can be uploaded by staff" on storage.objects;
drop policy if exists "Library files can be deleted by staff" on storage.objects;

create policy "Library files can be uploaded to owner folder" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'course-library'
    and split_part(name, '/', 1) = auth.uid()::text
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role in ('admin', 'instructor')
    )
  );

create policy "Library files can be deleted by owner or admin" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'course-library'
    and (
      exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
      or (
        split_part(name, '/', 1) = auth.uid()::text
        and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'instructor')
      )
    )
  );

commit;
