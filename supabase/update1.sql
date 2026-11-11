-- Run once in Supabase: SQL Editor > New query > paste > Run
-- Adds the "show Seen" setting.

alter table public.profiles
  add column if not exists read_receipts boolean not null default true;
