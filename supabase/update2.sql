-- Run once in Supabase: SQL Editor > New query > paste > Run
-- Adds reactions on chat messages (long-press a message to react).

alter table public.messages add column if not exists reaction text;

create or replace function public.react_message(msg uuid, emoji text) returns void
language sql security definer set search_path = public as $$
  update public.messages m
  set reaction = nullif(emoji, '')
  where m.id = msg
    and m.sender_id <> auth.uid()
    and exists (
      select 1 from public.conversations c
      where c.id = m.conversation_id and auth.uid() in (c.user_a, c.user_b)
    );
$$;
grant execute on function public.react_message(uuid, text) to authenticated;
