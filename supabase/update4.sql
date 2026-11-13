-- Run once in Supabase: SQL Editor > New query > paste > Run
-- Voice privacy, followers list (only for the owner), saved voices, voice history.

-- 1) Who can hear a voice: everyone, followers only, or only me
alter table public.voices
  add column if not exists visibility text not null default 'public'
  check (visibility in ('public', 'followers', 'private'));

drop policy if exists "voices visible" on public.voices;
create policy "voices visible" on public.voices for select to authenticated using (
  user_id = auth.uid()
  or (
    (kind = 'post' or (kind = 'story' and expires_at > now()))
    and (
      visibility = 'public'
      or (
        visibility = 'followers'
        and exists (
          select 1 from public.follows f
          where f.follower_id = auth.uid() and f.following_id = voices.user_id
        )
      )
    )
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = voices.user_id)
         or (b.blocker_id = voices.user_id and b.blocked_id = auth.uid())
    )
  )
);

-- 2) You can see who follows YOU (nobody else can)
drop policy if exists "follows see my followers" on public.follows;
create policy "follows see my followers" on public.follows
for select to authenticated using (following_id = auth.uid());

-- 3) Saved voices (private to you)
create table if not exists public.saves (
  user_id uuid not null references public.profiles(id) on delete cascade,
  voice_id uuid not null references public.voices(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, voice_id)
);
alter table public.saves enable row level security;
create policy "saves select own" on public.saves for select to authenticated using (user_id = auth.uid());
create policy "saves insert own" on public.saves for insert to authenticated with check (user_id = auth.uid());
create policy "saves delete own" on public.saves for delete to authenticated using (user_id = auth.uid());

-- 4) Voice history: voices you listened to (private to you)
create table if not exists public.voice_views (
  user_id uuid not null references public.profiles(id) on delete cascade,
  voice_id uuid not null references public.voices(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (user_id, voice_id)
);
alter table public.voice_views enable row level security;
create policy "views select own" on public.voice_views for select to authenticated using (user_id = auth.uid());
create policy "views insert own" on public.voice_views for insert to authenticated with check (user_id = auth.uid());
create policy "views update own" on public.voice_views for update to authenticated using (user_id = auth.uid());
create policy "views delete own" on public.voice_views for delete to authenticated using (user_id = auth.uid());
