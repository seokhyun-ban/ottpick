-- 오티티픽 Supabase 스키마
-- Supabase 대시보드 → SQL Editor 에 통째로 붙여 넣고 Run.
-- 로그인 없이 쓰도록 "익명 로그인(Anonymous sign-ins)"을 켜서 기기마다 사용자 ID를 만든다.

-- 1) 작품별 채팅 메시지
create table if not exists public.messages (
  id         uuid primary key default gen_random_uuid(),
  room       text not null check (char_length(room) between 1 and 40),          -- 작품 키 (예: m496243, t93405)
  uid        uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nickname   text not null default '익명' check (char_length(nickname) between 1 and 20),
  text       text not null check (char_length(text) between 1 and 300),
  spoiler    boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists messages_room_idx on public.messages (room, created_at desc);

-- 2) 작품 후기 (한 사람당 작품 하나에 후기 하나)
create table if not exists public.reviews (
  room       text not null check (char_length(room) between 1 and 40),
  uid        uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nickname   text not null default '익명' check (char_length(nickname) between 1 and 20),
  title      text check (char_length(title) <= 200),
  stars      smallint not null check (stars between 1 and 5),
  text       text not null default '' check (char_length(text) <= 200),
  spoiler    boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (room, uid)
);

-- 3) MY 기록 (추천 기록·볼래요·취향작·후기 목록을 기기 사이에 동기화)
create table if not exists public.user_state (
  uid        uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  data       jsonb not null default '{}'::jsonb check (pg_column_size(data) < 262144),
  updated_at timestamptz not null default now()
);

-- 접근 규칙: 채팅·후기는 누구나 읽고, 쓰기·지우기는 본인 것만. MY 기록은 본인만.
alter table public.messages   enable row level security;
alter table public.reviews    enable row level security;
alter table public.user_state enable row level security;

drop policy if exists "messages readable"   on public.messages;
drop policy if exists "messages insert own" on public.messages;
drop policy if exists "messages delete own" on public.messages;
create policy "messages readable"   on public.messages for select using (true);
create policy "messages insert own" on public.messages for insert to authenticated with check (uid = auth.uid());
create policy "messages delete own" on public.messages for delete to authenticated using (uid = auth.uid());

drop policy if exists "reviews readable"   on public.reviews;
drop policy if exists "reviews insert own" on public.reviews;
drop policy if exists "reviews update own" on public.reviews;
drop policy if exists "reviews delete own" on public.reviews;
create policy "reviews readable"   on public.reviews for select using (true);
create policy "reviews insert own" on public.reviews for insert to authenticated with check (uid = auth.uid());
create policy "reviews update own" on public.reviews for update to authenticated using (uid = auth.uid()) with check (uid = auth.uid());
create policy "reviews delete own" on public.reviews for delete to authenticated using (uid = auth.uid());

drop policy if exists "state own" on public.user_state;
create policy "state own" on public.user_state for all to authenticated using (uid = auth.uid()) with check (uid = auth.uid());

-- 작품별 앱 평점 (나중에 추천 점수의 '유저 평점'으로 사용)
create or replace view public.review_stats with (security_invoker = true) as
  select room, round(avg(stars)::numeric, 2) as avg_stars, count(*)::int as n
  from public.reviews group by room;

-- 채팅 실시간 전송
do $$ begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null; end $$;
