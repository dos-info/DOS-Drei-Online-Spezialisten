-- ============================================================
--  رفع الواجب — Hausaufgaben
--  شغّل هذا الملف مرة واحدة من: Supabase → SQL Editor
-- ============================================================

create table if not exists public.homework_submissions (
  id uuid primary key default gen_random_uuid(),
  student_profile_id uuid not null,
  student_name text,
  student_code text,
  group_name text,
  instructor_profile_id uuid,
  title text not null,
  note text,
  created_at timestamptz not null default now()
);

create table if not exists public.homework_files (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.homework_submissions(id) on delete cascade,
  file_name text not null,
  storage_path text not null,
  file_size bigint,
  mime_type text,
  created_at timestamptz not null default now()
);

create index if not exists homework_submissions_student_idx on public.homework_submissions(student_profile_id);
create index if not exists homework_submissions_instructor_idx on public.homework_submissions(instructor_profile_id);
create index if not exists homework_files_submission_idx on public.homework_files(submission_id);

alter table public.homework_submissions enable row level security;
alter table public.homework_files enable row level security;

-- دوال مساعدة
create or replace function public.hw_is_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('admin','accountant','staff'));
$$;

-- ---------- جدول الواجبات ----------
drop policy if exists hw_sub_select on public.homework_submissions;
create policy hw_sub_select on public.homework_submissions for select to authenticated
  using (student_profile_id = auth.uid() or instructor_profile_id = auth.uid() or public.hw_is_staff());

drop policy if exists hw_sub_insert on public.homework_submissions;
create policy hw_sub_insert on public.homework_submissions for insert to authenticated
  with check (student_profile_id = auth.uid());

drop policy if exists hw_sub_delete on public.homework_submissions;
create policy hw_sub_delete on public.homework_submissions for delete to authenticated
  using (student_profile_id = auth.uid() or instructor_profile_id = auth.uid() or public.hw_is_staff());

-- ---------- جدول الملفات ----------
drop policy if exists hw_files_select on public.homework_files;
create policy hw_files_select on public.homework_files for select to authenticated
  using (exists (select 1 from public.homework_submissions s where s.id = submission_id
        and (s.student_profile_id = auth.uid() or s.instructor_profile_id = auth.uid() or public.hw_is_staff())));

drop policy if exists hw_files_insert on public.homework_files;
create policy hw_files_insert on public.homework_files for insert to authenticated
  with check (exists (select 1 from public.homework_submissions s where s.id = submission_id and s.student_profile_id = auth.uid()));

drop policy if exists hw_files_delete on public.homework_files;
create policy hw_files_delete on public.homework_files for delete to authenticated
  using (exists (select 1 from public.homework_submissions s where s.id = submission_id
        and (s.student_profile_id = auth.uid() or s.instructor_profile_id = auth.uid() or public.hw_is_staff())));

-- ---------- التخزين (Storage) ----------
insert into storage.buckets (id, name, public) values ('homework', 'homework', false)
on conflict (id) do nothing;

-- مسار الملف: <student_profile_id>/<submission_id>/<file>
drop policy if exists hw_obj_insert on storage.objects;
create policy hw_obj_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'homework' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists hw_obj_select on storage.objects;
create policy hw_obj_select on storage.objects for select to authenticated
  using (bucket_id = 'homework' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.hw_is_staff()
    or exists (select 1 from public.homework_submissions s
               where s.student_profile_id::text = (storage.foldername(name))[1]
                 and s.instructor_profile_id = auth.uid())
  ));

drop policy if exists hw_obj_delete on storage.objects;
create policy hw_obj_delete on storage.objects for delete to authenticated
  using (bucket_id = 'homework' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.hw_is_staff()
    or exists (select 1 from public.homework_submissions s
               where s.student_profile_id::text = (storage.foldername(name))[1]
                 and s.instructor_profile_id = auth.uid())
  ));
