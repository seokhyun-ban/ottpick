-- 오티티픽 2단계: 신고 · 자동 숨김
-- 같은 글이 서로 다른 3명에게 신고되면 자동으로 숨겨진다(쓴 사람 본인에게만 보임).
-- '스포일러' 신고는 숨기지 않고 바로 스포일러 가림 처리만 한다.

alter table public.messages add column if not exists hidden boolean not null default false;
alter table public.reviews  add column if not exists hidden boolean not null default false;

create table if not exists public.reports (
  id         uuid primary key default gen_random_uuid(),
  kind       text not null check (kind in ('message','review')),
  room       text not null check (char_length(room) between 1 and 40),
  target_id  text not null check (char_length(target_id) <= 80),   -- 메시지 id, 또는 후기 작성자 uid
  target_uid uuid,
  reason     text not null check (reason in ('spoiler','abuse','spam','other')),
  memo       text check (char_length(memo) <= 200),
  reporter   uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (kind, target_id, reporter)
);
alter table public.reports enable row level security;
drop policy if exists "reports insert own" on public.reports;
create policy "reports insert own" on public.reports for insert to authenticated with check (reporter = auth.uid());
grant insert on public.reports to authenticated;

create or replace function public.handle_report() returns trigger
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  select count(distinct reporter) into n from public.reports
   where kind = new.kind and target_id = new.target_id and reason <> 'spoiler';
  if new.kind = 'message' then
    if new.reason = 'spoiler' then update public.messages set spoiler = true where id::text = new.target_id; end if;
    if n >= 3 then update public.messages set hidden = true where id::text = new.target_id; end if;
  else
    if new.reason = 'spoiler' then update public.reviews set spoiler = true where room = new.room and uid::text = new.target_id; end if;
    if n >= 3 then update public.reviews set hidden = true where room = new.room and uid::text = new.target_id; end if;
  end if;
  return new;
end $$;
drop trigger if exists on_report on public.reports;
create trigger on_report after insert on public.reports for each row execute function public.handle_report();

-- 숨겨진 글은 쓴 사람에게만 보인다
drop policy if exists "messages readable" on public.messages;
create policy "messages readable" on public.messages for select using (not hidden or uid = auth.uid());
drop policy if exists "reviews readable" on public.reviews;
create policy "reviews readable" on public.reviews for select using (not hidden or uid = auth.uid());

-- 숨김 표시는 사용자가 직접 풀 수 없게: 후기는 정해진 칸만 고칠 수 있다
revoke update on public.reviews from authenticated;
grant update (room, uid, nickname, title, stars, text, spoiler, updated_at) on public.reviews to authenticated;
