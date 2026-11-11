-- Run this once in Supabase: SQL Editor > New query > paste > Run
-- Voice chat between two people.

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  last_message_at timestamptz not null default now(),
  last_sender_id uuid,
  last_duration_ms int,
  created_at timestamptz not null default now(),
  check (user_a < user_b),
  unique (user_a, user_b)
);
create index on public.conversations (user_a);
create index on public.conversations (user_b);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  audio_path text not null,
  duration_ms int not null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index on public.messages (conversation_id, created_at desc);

alter table public.conversations enable row level security;
alter table public.messages enable row level security;

create policy "conversations members read" on public.conversations
for select to authenticated using (auth.uid() in (user_a, user_b));

create policy "messages members read" on public.messages
for select to authenticated using (
  exists (
    select 1 from public.conversations c
    where c.id = conversation_id and auth.uid() in (c.user_a, c.user_b)
  )
);

create policy "messages send" on public.messages
for insert to authenticated with check (
  sender_id = auth.uid()
  and exists (
    select 1 from public.conversations c
    where c.id = conversation_id
      and auth.uid() in (c.user_a, c.user_b)
      and not exists (
        select 1 from public.blocks b
        where (b.blocker_id = c.user_a and b.blocked_id = c.user_b)
           or (b.blocker_id = c.user_b and b.blocked_id = c.user_a)
      )
  )
);

create policy "messages delete own" on public.messages
for delete to authenticated using (sender_id = auth.uid());

-- Start (or find) the chat with another person
create function public.get_or_create_conversation(other uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare a uuid; b uuid; cid uuid;
begin
  if other is null or other = auth.uid() then
    raise exception 'invalid user';
  end if;
  if exists (
    select 1 from public.blocks
    where (blocker_id = auth.uid() and blocked_id = other)
       or (blocker_id = other and blocked_id = auth.uid())
  ) then
    raise exception 'blocked';
  end if;
  a := least(auth.uid(), other);
  b := greatest(auth.uid(), other);
  select id into cid from public.conversations where user_a = a and user_b = b;
  if cid is null then
    insert into public.conversations (user_a, user_b) values (a, b) returning id into cid;
  end if;
  return cid;
end $$;
grant execute on function public.get_or_create_conversation(uuid) to authenticated;

-- Keep the chat list preview up to date
create function public.on_message_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.conversations
  set last_message_at = new.created_at,
      last_sender_id = new.sender_id,
      last_duration_ms = new.duration_ms
  where id = new.conversation_id;
  return new;
end $$;
create trigger messages_after_insert
after insert on public.messages
for each row execute function public.on_message_insert();

-- Mark the other person's messages as seen
create function public.mark_read(conv uuid) returns void
language sql security definer set search_path = public as $$
  update public.messages set read_at = now()
  where conversation_id = conv
    and sender_id <> auth.uid()
    and read_at is null
    and exists (
      select 1 from public.conversations c
      where c.id = conv and auth.uid() in (c.user_a, c.user_b)
    );
$$;
grant execute on function public.mark_read(uuid) to authenticated;
