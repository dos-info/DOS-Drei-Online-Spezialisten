-- ============================================================
--  المحادثات — Chat  (شغّل هذا الملف مرة واحدة من Supabase → SQL Editor)
--  جماعي: كل أعضاء الجروب + المحاضر | فردي: الطالب + المحاضر | الأدمن يرى ويتحكم في الكل
-- ============================================================

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  room_type text not null check (room_type in ('group','direct')),
  group_name text,
  student_profile_id uuid,
  sender_profile_id uuid not null,
  sender_name text,
  sender_role text,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists chat_messages_group_idx on public.chat_messages(room_type, group_name, created_at desc);
create index if not exists chat_messages_direct_idx on public.chat_messages(room_type, student_profile_id, created_at desc);

create table if not exists public.chat_locks (
  room_key text primary key,
  locked boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.chat_messages enable row level security;
alter table public.chat_locks enable row level security;

-- ---------- دوال مساعدة ----------
create or replace function public.chat_is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p where p.id::text = auth.uid()::text and p.role = 'admin');
$$;

create or replace function public.chat_is_instructor()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p where p.id::text = auth.uid()::text and p.role = 'instructor');
$$;

create or replace function public.chat_can_access(p_type text, p_group text, p_student uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when public.chat_is_admin() then true
    when p_type = 'group' then
      exists (select 1 from public.students s where s.profile_id::text = auth.uid()::text and s.group_name = p_group)
      or exists (select 1 from public.students s where s.instructor_id::text = auth.uid()::text and s.group_name = p_group)
    when p_type = 'direct' then
      p_student::text = auth.uid()::text
      or exists (select 1 from public.students s where s.profile_id::text = p_student::text and s.instructor_id::text = auth.uid()::text)
    else false end;
$$;

create or replace function public.chat_is_locked(p_type text, p_group text, p_student uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select l.locked from public.chat_locks l
    where l.room_key = case when p_type = 'group' then 'g:' || p_group else 'd:' || p_student::text end), false);
$$;

-- ---------- سياسات الرسائل ----------
drop policy if exists chat_msg_select on public.chat_messages;
create policy chat_msg_select on public.chat_messages for select to authenticated
  using (public.chat_can_access(room_type, group_name, student_profile_id));

drop policy if exists chat_msg_insert on public.chat_messages;
create policy chat_msg_insert on public.chat_messages for insert to authenticated
  with check (
    sender_profile_id::text = auth.uid()::text
    and public.chat_can_access(room_type, group_name, student_profile_id)
    and (public.chat_is_admin() or public.chat_is_instructor()
         or not public.chat_is_locked(room_type, group_name, student_profile_id))
  );

drop policy if exists chat_msg_delete on public.chat_messages;
create policy chat_msg_delete on public.chat_messages for delete to authenticated
  using (
    public.chat_is_admin()
    or sender_profile_id::text = auth.uid()::text
    or (public.chat_is_instructor() and public.chat_can_access(room_type, group_name, student_profile_id))
  );

-- ---------- سياسات القفل (الأدمن فقط يتحكم) ----------
drop policy if exists chat_lock_select on public.chat_locks;
create policy chat_lock_select on public.chat_locks for select to authenticated using (true);

drop policy if exists chat_lock_admin on public.chat_locks;
create policy chat_lock_admin on public.chat_locks for all to authenticated
  using (public.chat_is_admin()) with check (public.chat_is_admin());

-- ---------- الوقت الحقيقي (Realtime) ----------
do $$ begin
  begin alter publication supabase_realtime add table public.chat_messages; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.chat_locks; exception when duplicate_object then null; end;
end $$;
