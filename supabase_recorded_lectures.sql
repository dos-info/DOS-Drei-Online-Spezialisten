-- =====================================================================
--  DOS Akademie — المحاضرات المسجلة وملحقاتها (Aufgezeichnete Vorlesungen)
--  شغّل هذا الملف مرة واحدة من: Supabase → SQL Editor → New query → Run
--  آمن لإعادة التشغيل (idempotent).
-- =====================================================================

create extension if not exists pgcrypto;

-- 1) الجداول ----------------------------------------------------------
create table if not exists public.recorded_lectures (
  id                    uuid primary key default gen_random_uuid(),
  group_name            text,                                -- اسم الجروب (نفس group_name عند الطالب)
  level                 text,                                -- قديم: لم يعد مستخدمًا
  title                 text not null,
  lecture_date          date not null default current_date,
  url                   text,                                -- رابط المحاضرة المسجلة
  description           text,
  visible               boolean not null default true,
  instructor_profile_id uuid references public.profiles(id) on delete set null,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create table if not exists public.recorded_lecture_attachments (
  id           uuid primary key default gen_random_uuid(),
  lecture_id   uuid not null references public.recorded_lectures(id) on delete cascade,
  file_name    text not null,
  storage_path text not null,
  file_size    bigint,
  mime_type    text,
  created_at   timestamptz not null default now()
);

-- ترقية: لو كنت شغّلت النسخة السابقة (التقسيم بالمستوى) فهذه الأسطر تحوّلها للجروب
alter table public.recorded_lectures add column if not exists group_name text;
alter table public.recorded_lectures alter column level drop not null;

create index if not exists recorded_lectures_group_date_idx on public.recorded_lectures (group_name, lecture_date desc);
create index if not exists recorded_lecture_attachments_lecture_idx on public.recorded_lecture_attachments (lecture_id);

-- 2) دوال مساعدة (security definer لتجنب مشاكل RLS المتداخلة) ------------
create or replace function public.dos_current_role()
returns text language sql stable security definer set search_path = public as
$$ select role::text from public.profiles where id = auth.uid() $$;

create or replace function public.dos_current_student_group()
returns text language sql stable security definer set search_path = public as
$$ select group_name::text from public.students where profile_id = auth.uid() $$;

create or replace function public.dos_is_staff()
returns boolean language sql stable security definer set search_path = public as
$$ select coalesce(public.dos_current_role() in ('admin','accountant','staff','instructor'), false) $$;

create or replace function public.dos_is_office()
returns boolean language sql stable security definer set search_path = public as
$$ select coalesce(public.dos_current_role() in ('admin','accountant','staff'), false) $$;

-- 3) RLS ---------------------------------------------------------------
alter table public.recorded_lectures enable row level security;
alter table public.recorded_lecture_attachments enable row level security;

-- المحاضرات: الموظفون/المحاضرون يرون الكل، الطالب يرى المرئي من جروبه فقط
drop policy if exists "rl_select" on public.recorded_lectures;
create policy "rl_select" on public.recorded_lectures for select to authenticated
using (
  public.dos_is_staff()
  or (
    visible = true
    and btrim(coalesce(group_name, '')) <> ''
    and lower(btrim(group_name)) = lower(btrim(coalesce(public.dos_current_student_group(), '')))
  )
);

-- الإضافة: الإدارة/الموظفون لأي محاضرة، والمحاضر لمحاضراته فقط
drop policy if exists "rl_insert" on public.recorded_lectures;
create policy "rl_insert" on public.recorded_lectures for insert to authenticated
with check (
  public.dos_is_office()
  or (public.dos_current_role() = 'instructor' and instructor_profile_id = auth.uid())
);

drop policy if exists "rl_update" on public.recorded_lectures;
create policy "rl_update" on public.recorded_lectures for update to authenticated
using (
  public.dos_is_office()
  or (public.dos_current_role() = 'instructor' and instructor_profile_id = auth.uid())
)
with check (
  public.dos_is_office()
  or (public.dos_current_role() = 'instructor' and instructor_profile_id = auth.uid())
);

drop policy if exists "rl_delete" on public.recorded_lectures;
create policy "rl_delete" on public.recorded_lectures for delete to authenticated
using (
  public.dos_is_office()
  or (public.dos_current_role() = 'instructor' and instructor_profile_id = auth.uid())
);

-- الملحقات: تتبع صلاحية المحاضرة الأم (الاستعلام الفرعي يمرّ عبر RLS المحاضرات)
drop policy if exists "rla_select" on public.recorded_lecture_attachments;
create policy "rla_select" on public.recorded_lecture_attachments for select to authenticated
using ( exists (select 1 from public.recorded_lectures l where l.id = lecture_id) );

drop policy if exists "rla_insert" on public.recorded_lecture_attachments;
create policy "rla_insert" on public.recorded_lecture_attachments for insert to authenticated
with check (
  exists (
    select 1 from public.recorded_lectures l
    where l.id = lecture_id
      and (public.dos_is_office() or (public.dos_current_role() = 'instructor' and l.instructor_profile_id = auth.uid()))
  )
);

drop policy if exists "rla_delete" on public.recorded_lecture_attachments;
create policy "rla_delete" on public.recorded_lecture_attachments for delete to authenticated
using (
  exists (
    select 1 from public.recorded_lectures l
    where l.id = lecture_id
      and (public.dos_is_office() or (public.dos_current_role() = 'instructor' and l.instructor_profile_id = auth.uid()))
  )
);

-- 4) التخزين (Storage) — bucket خاص، كل الصيغ مسموحة ----------------------
insert into storage.buckets (id, name, public)
values ('recorded-lectures', 'recorded-lectures', false)
on conflict (id) do nothing;

-- القراءة: فقط إذا كان الملف مرتبطًا بمحاضرة يحق للمستخدم رؤيتها
drop policy if exists "rl_files_select" on storage.objects;
create policy "rl_files_select" on storage.objects for select to authenticated
using (
  bucket_id = 'recorded-lectures'
  and exists (select 1 from public.recorded_lecture_attachments a where a.storage_path = name)
);

-- الرفع: المسار يبدأ بمعرّف المحاضرة، والرافع يجب أن يملك صلاحية على تلك المحاضرة
drop policy if exists "rl_files_insert" on storage.objects;
create policy "rl_files_insert" on storage.objects for insert to authenticated
with check (
  bucket_id = 'recorded-lectures'
  and exists (
    select 1 from public.recorded_lectures l
    where l.id::text = (storage.foldername(name))[1]
      and (public.dos_is_office() or (public.dos_current_role() = 'instructor' and l.instructor_profile_id = auth.uid()))
  )
);

-- الحذف: نفس شرط الرفع
drop policy if exists "rl_files_delete" on storage.objects;
create policy "rl_files_delete" on storage.objects for delete to authenticated
using (
  bucket_id = 'recorded-lectures'
  and (
    public.dos_is_office()
    or exists (
      select 1 from public.recorded_lectures l
      where l.id::text = (storage.foldername(name))[1]
        and public.dos_current_role() = 'instructor' and l.instructor_profile_id = auth.uid()
    )
  )
);

-- ملاحظة: الحد الأقصى لحجم الملف الواحد يتحكم به Supabase (الافتراضي 50MB في الخطة المجانية)
-- ويمكن رفعه من: Storage → Settings → Global file size limit.
