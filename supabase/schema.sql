-- Winner Stays On: ping pong Elo ladder
-- Run once in a new Supabase project (SQL editor). Everyone can read the
-- ladder. Only emails listed in public.organisers can change it.
-- Each row in public.tables is a physical table. A session is live while
-- session_id is set and active_at is less than 10 minutes old.

create table public.players (
  id text primary key check (char_length(id) between 1 and 64),
  name text not null check (char_length(btrim(name)) between 1 and 40),
  archived boolean not null default false,
  created_at timestamptz not null default now(),
  added_by uuid default auth.uid()
);

create table public.games (
  id text primary key check (char_length(id) between 1 and 64),
  w text not null references public.players (id),
  l text not null references public.players (id),
  ws smallint not null check (ws between 0 and 99),
  ls smallint not null check (ls between 0 and 99),
  t smallint not null default 0 check (t between 0 and 99),
  at bigint not null,
  v boolean not null default false,
  table_no smallint,
  session_id text,
  recorded_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  constraint games_two_players check (w <> l),
  constraint games_winner_scores_more check (ws > ls)
);
create index games_at_idx on public.games (at);
create index games_w_idx on public.games (w);
create index games_l_idx on public.games (l);
create index games_session_idx on public.games (session_id);

create table public.tables (
  id smallint primary key check (id between 1 and 9),
  name text not null,
  session_id text,
  started_at bigint,
  active_at bigint,
  a text references public.players (id),
  b text references public.players (id),
  queue text[] not null default '{}',
  target smallint check (target in (3, 5, 11)),
  streak integer not null default 0 check (streak >= 0),
  rejoin boolean not null default true,
  updated_at timestamptz not null default now()
);
insert into public.tables (id, name) values (1, 'Table 1'), (2, 'Table 2');

create table public.organisers (
  email text primary key check (email = lower(email))
);

alter table public.players enable row level security;
alter table public.games enable row level security;
alter table public.tables enable row level security;
alter table public.organisers enable row level security;

-- The organiser check lives outside the API schema so it can't be called directly
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create or replace function private.is_organiser()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.organisers o
    where o.email = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
revoke all on function private.is_organiser() from public, anon;
grant execute on function private.is_organiser() to authenticated;

grant select on public.players, public.games, public.tables to anon, authenticated;
grant insert, update on public.players to authenticated;
grant insert, update, delete on public.games to authenticated;
grant update on public.tables to authenticated;
grant select on public.organisers to authenticated;

-- Everyone can watch the ladder
create policy "Anyone can read players" on public.players for select to anon, authenticated using (true);
create policy "Anyone can read games" on public.games for select to anon, authenticated using (true);
create policy "Anyone can read tables" on public.tables for select to anon, authenticated using (true);

-- Only organisers can change it
create policy "Organisers add players" on public.players for insert to authenticated with check ((select private.is_organiser()));
create policy "Organisers edit players" on public.players for update to authenticated using ((select private.is_organiser())) with check ((select private.is_organiser()));
create policy "Organisers add games" on public.games for insert to authenticated with check ((select private.is_organiser()));
create policy "Organisers edit games" on public.games for update to authenticated using ((select private.is_organiser())) with check ((select private.is_organiser()));
create policy "Organisers remove games" on public.games for delete to authenticated using ((select private.is_organiser()));
create policy "Organisers run tables" on public.tables for update to authenticated using ((select private.is_organiser())) with check ((select private.is_organiser()));

-- Organisers can see that they are one, so the app shows them the controls
create policy "Organisers see their own row" on public.organisers for select to authenticated using (email = lower(coalesce(auth.jwt() ->> 'email', '')));

-- Live updates for everyone watching
alter publication supabase_realtime add table public.players, public.games, public.tables;

-- Then add yourself as an organiser (run separately, with your own email):
-- insert into public.organisers (email) values ('you@example.com');
