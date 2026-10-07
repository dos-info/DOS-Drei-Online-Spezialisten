-- ============================================================
--  الرسائل الصوتية + المكالمات عبر الإنترنت
--  شغّل هذا الملف مرة واحدة من Supabase → SQL Editor
--  (بعد ملف supabase_chat.sql)
-- ============================================================

-- ---------- 1) أعمدة جديدة في الرسائل ----------
alter table public.chat_messages add column if not exists kind text not null default 'text';
alter table public.chat_messages add column if not exists media_path text;
alter table public.chat_messages add column if not exists media_duration integer;

alter table public.chat_messages drop constraint if exists chat_messages_kind_check;
alter table public.chat_messages add constraint chat_messages_kind_check check (kind in ('text','voice','call'));

-- ---------- 2) تخزين التسجيلات الصوتية ----------
insert into storage.buckets (id, name, public, file_size_limit)
values ('chat-voice', 'chat-voice', false, 15728640)
on conflict (id) do nothing;

-- مسار الملف: <sender_profile_id>/<uuid>.<ext>
drop policy if exists chatvoice_insert on storage.objects;
create policy chatvoice_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'chat-voice' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists chatvoice_select on storage.objects;
create policy chatvoice_select on storage.objects for select to authenticated
  using (bucket_id = 'chat-voice' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.chat_is_admin()
    or exists (select 1 from public.chat_messages m
               where m.media_path = name and public.chat_can_access(m.room_type, m.group_name, m.student_profile_id))
  ));

drop policy if exists chatvoice_delete on storage.objects;
create policy chatvoice_delete on storage.objects for delete to authenticated
  using (bucket_id = 'chat-voice' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.chat_is_admin()
    or (public.chat_is_instructor() and exists (select 1 from public.chat_messages m
               where m.media_path = name and public.chat_can_access(m.room_type, m.group_name, m.student_profile_id)))
  ));

-- ---------- 3) إشارات المكالمات (Signaling) ----------
create table if not exists public.call_signals (
  id uuid primary key default gen_random_uuid(),
  call_id uuid not null,
  from_id uuid not null,
  to_id uuid not null,
  kind text not null check (kind in ('invite','accept','reject','busy','cancel','hangup','offer','answer','ice')),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists call_signals_to_idx on public.call_signals(to_id, created_at desc);
create index if not exists call_signals_call_idx on public.call_signals(call_id);

alter table public.call_signals enable row level security;

-- من يُسمح له بالاتصال بمن: الأدمن مع الجميع، والمحاضر مع طلابه (والعكس)
create or replace function public.call_allowed(p_from uuid, p_to uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p where p.id::text = p_from::text and p.role = 'admin')
      or exists (select 1 from public.profiles p where p.id::text = p_to::text and p.role = 'admin')
      or exists (select 1 from public.students s
                 where (s.profile_id::text = p_from::text and s.instructor_id::text = p_to::text)
                    or (s.profile_id::text = p_to::text and s.instructor_id::text = p_from::text));
$$;

drop policy if exists call_sig_insert on public.call_signals;
create policy call_sig_insert on public.call_signals for insert to authenticated
  with check (from_id::text = auth.uid()::text and public.call_allowed(from_id, to_id));

drop policy if exists call_sig_select on public.call_signals;
create policy call_sig_select on public.call_signals for select to authenticated
  using (from_id::text = auth.uid()::text or to_id::text = auth.uid()::text);

drop policy if exists call_sig_delete on public.call_signals;
create policy call_sig_delete on public.call_signals for delete to authenticated
  using (from_id::text = auth.uid()::text or to_id::text = auth.uid()::text);

do $$ begin
  begin alter publication supabase_realtime add table public.call_signals; exception when duplicate_object then null; end;
end $$;

-- (اختياري) تنظيف الإشارات القديمة يدويًا من وقت لآخر:
-- delete from public.call_signals where created_at < now() - interval '1 day';
