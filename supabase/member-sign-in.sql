-- Sign in with name and student number, no email.
-- Players sign in with their name. The first sign-in sets their student
-- number, later sign-ins must match it. Numbers are stored as bcrypt hashes.
-- Every change goes through the functions below, which check a session
-- token. Signed-in players run tables, add players and record games.
-- Only organisers rename, archive, void and reset sign-ins.

create table private.members (
  player_id text primary key references public.players (id) on delete cascade,
  number_hash text,
  is_organiser boolean not null default false,
  failed smallint not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);

create table private.sessions (
  token_hash text primary key,
  player_id text not null references public.players (id) on delete cascade,
  created_at timestamptz not null default now(),
  last_used timestamptz not null default now()
);
create index sessions_player_idx on private.sessions (player_id);

revoke all on private.members, private.sessions from public, anon, authenticated;

create unique index players_name_unique on public.players (lower(btrim(name)));
alter table public.games add column if not exists recorded_by_player text;
alter table public.games add column if not exists removed boolean not null default false;

-- Who a token belongs to. Raises 28000 when the token is missing or stale.
create or replace function private.member(p_token text, p_need_organiser boolean default false)
returns private.members
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player text;
  v_m private.members;
begin
  update private.sessions s set last_used = now()
  where s.token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex')
    and s.last_used > now() - interval '180 days'
  returning s.player_id into v_player;
  if v_player is null then
    raise exception 'Sign in again' using errcode = '28000';
  end if;
  select * into v_m from private.members m where m.player_id = v_player;
  if p_need_organiser and not coalesce(v_m.is_organiser, false) then
    raise exception 'Only organisers can do that' using errcode = '42501';
  end if;
  return v_m;
end;
$$;
revoke all on function private.member(text, boolean) from public, anon, authenticated;

create or replace function public.wso_sign_in(p_name text, p_number text)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text := upper(regexp_replace(coalesce(p_number, ''), '[\s-]', '', 'g'));
  v_name text := lower(btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')));
  v_p public.players;
  v_m private.members;
  v_token text;
  v_first boolean;
begin
  if char_length(v_key) not between 3 and 32 then
    return json_build_object('error', 'bad_number');
  end if;
  select * into v_p from public.players p where lower(btrim(p.name)) = v_name and not p.archived;
  if not found then
    return json_build_object('error', 'no_player');
  end if;
  insert into private.members (player_id) values (v_p.id) on conflict (player_id) do nothing;
  select * into v_m from private.members m where m.player_id = v_p.id for update;
  if v_m.locked_until is not null and v_m.locked_until > now() then
    return json_build_object('error', 'locked', 'minutes', ceil(extract(epoch from v_m.locked_until - now()) / 60));
  end if;
  v_first := v_m.number_hash is null;
  if v_first then
    update private.members m set number_hash = extensions.crypt(v_key, extensions.gen_salt('bf', 8)), failed = 0, locked_until = null, updated_at = now()
    where m.player_id = v_p.id;
  elsif v_m.number_hash <> extensions.crypt(v_key, v_m.number_hash) then
    update private.members m
    set failed = case when m.failed + 1 >= 5 then 0 else m.failed + 1 end,
        locked_until = case when m.failed + 1 >= 5 then now() + interval '15 minutes' else null end,
        updated_at = now()
    where m.player_id = v_p.id;
    return json_build_object('error', 'wrong_number');
  else
    update private.members m set failed = 0, locked_until = null where m.player_id = v_p.id;
  end if;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into private.sessions (token_hash, player_id)
  values (encode(extensions.digest(v_token, 'sha256'), 'hex'), v_p.id);
  return json_build_object('token', v_token, 'player_id', v_p.id, 'name', v_p.name, 'organiser', v_m.is_organiser, 'first', v_first);
end;
$$;

create or replace function public.wso_me(p_token text)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m private.members;
  v_name text;
begin
  begin
    v_m := private.member(p_token);
  exception when sqlstate '28000' then
    return null;
  end;
  select p.name into v_name from public.players p where p.id = v_m.player_id and not p.archived;
  if v_name is null then return null; end if;
  return json_build_object('player_id', v_m.player_id, 'name', v_name, 'organiser', v_m.is_organiser);
end;
$$;

create or replace function public.wso_sign_out(p_token text)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.sessions s set last_used = '-infinity'
  where s.token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
$$;

create or replace function public.wso_add_player(p_token text, p_id text, p_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.member(p_token);
  insert into public.players (id, name) values (p_id, btrim(regexp_replace(p_name, '\s+', ' ', 'g')));
end;
$$;

create or replace function public.wso_update_player(p_token text, p_id text, p_name text default null, p_archived boolean default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.member(p_token, true);
  update public.players p
  set name = coalesce(btrim(regexp_replace(p_name, '\s+', ' ', 'g')), p.name),
      archived = coalesce(p_archived, p.archived)
  where p.id = p_id;
  if not found then raise exception 'No such player' using errcode = 'P0002'; end if;
end;
$$;

create or replace function public.wso_add_game(p_token text, p_id text, p_game jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m private.members := private.member(p_token);
begin
  insert into public.games (id, w, l, ws, ls, t, at, table_no, session_id, recorded_by_player)
  values (p_id, p_game ->> 'w', p_game ->> 'l', (p_game ->> 'ws')::smallint, (p_game ->> 'ls')::smallint,
          coalesce((p_game ->> 't')::smallint, 0), (p_game ->> 'at')::bigint,
          (p_game ->> 'table_no')::smallint, p_game ->> 'session_id', v_m.player_id);
end;
$$;

-- Undo hides a game but keeps it on record. Organisers can undo any game,
-- whoever recorded a game can undo it for 10 minutes.
create or replace function public.wso_remove_game(p_token text, p_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m private.members := private.member(p_token);
begin
  update public.games g set removed = true
  where g.id = p_id
    and (v_m.is_organiser or (g.recorded_by_player = v_m.player_id and g.created_at > now() - interval '10 minutes'));
  if not found then raise exception 'Only organisers can remove that game' using errcode = '42501'; end if;
end;
$$;

create or replace function public.wso_void_game(p_token text, p_id text, p_void boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.member(p_token, true);
  update public.games g set v = p_void where g.id = p_id;
  if not found then raise exception 'No such game' using errcode = 'P0002'; end if;
end;
$$;

create or replace function public.wso_set_table(p_token text, p_no smallint, p_t jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.member(p_token);
  update public.tables t set
    session_id = p_t ->> 'session_id',
    started_at = (p_t ->> 'started_at')::bigint,
    active_at = (p_t ->> 'active_at')::bigint,
    a = p_t ->> 'a',
    b = p_t ->> 'b',
    queue = coalesce(array(select jsonb_array_elements_text(p_t -> 'queue')), '{}'),
    target = (p_t ->> 'target')::smallint,
    streak = coalesce((p_t ->> 'streak')::integer, 0),
    rejoin = coalesce((p_t ->> 'rejoin')::boolean, true),
    updated_at = now()
  where t.id = p_no;
  if not found then raise exception 'No such table' using errcode = 'P0002'; end if;
end;
$$;

-- Clears a player's student number so they can set a new one
create or replace function public.wso_reset_sign_in(p_token text, p_player text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.member(p_token, true);
  update private.members m set number_hash = null, failed = 0, locked_until = null, updated_at = now() where m.player_id = p_player;
  update private.sessions s set last_used = '-infinity' where s.player_id = p_player;
end;
$$;

revoke all on function public.wso_sign_in(text, text), public.wso_me(text), public.wso_sign_out(text),
  public.wso_add_player(text, text, text), public.wso_update_player(text, text, text, boolean),
  public.wso_add_game(text, text, jsonb), public.wso_remove_game(text, text), public.wso_void_game(text, text, boolean),
  public.wso_set_table(text, smallint, jsonb), public.wso_reset_sign_in(text, text) from public;
grant execute on function public.wso_sign_in(text, text), public.wso_me(text), public.wso_sign_out(text),
  public.wso_add_player(text, text, text), public.wso_update_player(text, text, text, boolean),
  public.wso_add_game(text, text, jsonb), public.wso_remove_game(text, text), public.wso_void_game(text, text, boolean),
  public.wso_set_table(text, smallint, jsonb), public.wso_reset_sign_in(text, text) to anon, authenticated;

-- Then make yourself an organiser (run separately, with your own player name):
-- insert into private.members (player_id, is_organiser) select id, true from public.players where name = 'You'
-- on conflict (player_id) do update set is_organiser = true;
