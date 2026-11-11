-- Run this once in Supabase: SQL Editor > New query > paste > Run

create extension if not exists pgcrypto;

-- PROFILES
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (username ~ '^[a-z0-9_.]{3,20}$'),
  nickname text check (char_length(nickname) <= 30),
  avatar_path text,
  age int check (age between 13 and 120),
  country text,
  hobbies text[] not null default '{}' check (cardinality(hobbies) <= 5),
  languages text[] not null default '{}',
  story_hours int not null default 24 check (story_hours in (6, 12, 18, 24)),
  save_archive boolean not null default true,
  created_at timestamptz not null default now()
);

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username)
  values (new.id, lower(new.raw_user_meta_data->>'username'));
  return new;
end $$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

create function public.username_available(u text) returns boolean
language sql security definer set search_path = public as $$
  select not exists (select 1 from public.profiles where username = lower(u));
$$;
grant execute on function public.username_available(text) to anon, authenticated;

-- VOICES (posts and stories)
create table public.voices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  audio_path text not null,
  caption text check (char_length(caption) <= 60),
  mood text not null check (mood in ('happy','sad','funny','help','thinking','frustrated','calm')),
  duration_ms int not null,
  kind text not null default 'post' check (kind in ('post','story')),
  expires_at timestamptz,
  created_at timestamptz not null default now()
);
create index on public.voices (created_at desc);
create index on public.voices (user_id);

-- Voice comments
create table public.comments (
  id uuid primary key default gen_random_uuid(),
  voice_id uuid not null references public.voices(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  audio_path text not null,
  duration_ms int not null,
  created_at timestamptz not null default now()
);

create table public.likes (
  user_id uuid not null references public.profiles(id) on delete cascade,
  voice_id uuid not null references public.voices(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, voice_id)
);

create table public.reposts (
  user_id uuid not null references public.profiles(id) on delete cascade,
  voice_id uuid not null references public.voices(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, voice_id)
);

create table public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  following_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  check (follower_id <> following_id)
);

create table public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  target_type text not null check (target_type in ('voice','profile','comment','message')),
  target_id uuid not null,
  reason text,
  created_at timestamptz not null default now()
);

-- ROW LEVEL SECURITY
alter table public.profiles enable row level security;
alter table public.voices enable row level security;
alter table public.comments enable row level security;
alter table public.likes enable row level security;
alter table public.reposts enable row level security;
alter table public.follows enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;

create policy "profiles readable" on public.profiles for select to authenticated using (true);
create policy "profiles update own" on public.profiles for update to authenticated using (id = auth.uid());

create policy "voices visible" on public.voices for select to authenticated using (
  (user_id = auth.uid())
  or (
    (kind = 'post' or (kind = 'story' and expires_at > now()))
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = voices.user_id)
         or (b.blocker_id = voices.user_id and b.blocked_id = auth.uid())
    )
  )
);
create policy "voices insert own" on public.voices for insert to authenticated with check (user_id = auth.uid());
create policy "voices delete own" on public.voices for delete to authenticated using (user_id = auth.uid());

create policy "comments readable" on public.comments for select to authenticated using (true);
create policy "comments insert own" on public.comments for insert to authenticated with check (user_id = auth.uid());
create policy "comments delete own or on my voice" on public.comments for delete to authenticated using (
  user_id = auth.uid()
  or exists (select 1 from public.voices v where v.id = voice_id and v.user_id = auth.uid())
);

-- Likes and reposts are only visible to the person who did them and to the voice owner
-- (counts stay hidden from everyone else)
create policy "likes visible" on public.likes for select to authenticated using (
  user_id = auth.uid()
  or exists (select 1 from public.voices v where v.id = voice_id and v.user_id = auth.uid())
);
create policy "likes insert own" on public.likes for insert to authenticated with check (user_id = auth.uid());
create policy "likes delete own" on public.likes for delete to authenticated using (user_id = auth.uid());

create policy "reposts visible" on public.reposts for select to authenticated using (
  user_id = auth.uid()
  or exists (select 1 from public.voices v where v.id = voice_id and v.user_id = auth.uid())
);
create policy "reposts insert own" on public.reposts for insert to authenticated with check (user_id = auth.uid());
create policy "reposts delete own" on public.reposts for delete to authenticated using (user_id = auth.uid());

-- You can only see who YOU follow, never who follows you
create policy "follows select own" on public.follows for select to authenticated using (follower_id = auth.uid());
create policy "follows insert own" on public.follows for insert to authenticated with check (follower_id = auth.uid());
create policy "follows delete own" on public.follows for delete to authenticated using (follower_id = auth.uid());

create policy "blocks select own" on public.blocks for select to authenticated using (blocker_id = auth.uid());
create policy "blocks insert own" on public.blocks for insert to authenticated with check (blocker_id = auth.uid());
create policy "blocks delete own" on public.blocks for delete to authenticated using (blocker_id = auth.uid());

create policy "reports insert own" on public.reports for insert to authenticated with check (reporter_id = auth.uid());

-- STORAGE
insert into storage.buckets (id, name, public)
values ('voices', 'voices', false), ('avatars', 'avatars', true)
on conflict (id) do nothing;

create policy "upload to own folder" on storage.objects for insert to authenticated
with check (bucket_id in ('voices','avatars') and (storage.foldername(name))[1] = auth.uid()::text);
create policy "delete own files" on storage.objects for delete to authenticated
using (bucket_id in ('voices','avatars') and (storage.foldername(name))[1] = auth.uid()::text);
create policy "read voices" on storage.objects for select to authenticated using (bucket_id = 'voices');
create policy "read avatars" on storage.objects for select using (bucket_id = 'avatars');
