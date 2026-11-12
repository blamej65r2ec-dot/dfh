-- Run once in Supabase: SQL Editor > New query > paste > Run
-- Lets a voice reply to a story show as a story card in the chat.

alter table public.messages
  add column if not exists story_id uuid references public.voices(id) on delete set null;
