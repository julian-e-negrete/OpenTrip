-- Crews: named groups of friends who can see each other live on the map
-- during a ride (position, and optionally speed and lean angle), and
-- navigate to one another. Run this once in the SQL Editor, after
-- schema.sql and friends.sql. See docs/CLOUD_SYNC_SETUP.md.
--
-- Same posture as friends.sql: crews/crew_members only get SELECT
-- policies, and every write that needs a
-- check-then-act decision ("is this person actually your friend?", "are
-- you the owner?", "was that the last member?") goes through a
-- `security definer` function. Every function pairs its `grant ... to
-- authenticated` with a `revoke ... from anon, public` — see the comment
-- at the top of friends.sql for why both are needed.
--
-- Privacy model:
-- - You can only add someone to a crew if they're an accepted friend of
--   yours, so nobody ends up broadcasting to a stranger.
-- - Sharing is per crew, per member: share_location / share_speed /
--   share_lean on *your own* crew_members row decide what *that crew*
--   sees of you. Location off means you're invisible to that crew.
-- - live_positions is only directly readable for your own row (PostgREST
--   needs that for upserts): the only way to read anyone else's position
--   is get_crew_live_positions(), which applies the sharing flags above
--   and drops anything older than 2 minutes.
-- - The app deletes your live_positions row when a ride ends.

create table if not exists public.crews (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 40),
  owner_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.crew_members (
  crew_id uuid not null references public.crews(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  share_location boolean not null default true,
  share_speed boolean not null default true,
  share_lean boolean not null default true,
  joined_at timestamptz not null default now(),
  primary key (crew_id, user_id)
);

create index if not exists crew_members_user_idx on public.crew_members(user_id);

create table if not exists public.live_positions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  latitude double precision not null,
  longitude double precision not null,
  speed_kph double precision,
  lean_deg double precision,
  heading_deg double precision,
  updated_at timestamptz not null default now()
);

-- Server-stamped freshness: the 2-minute cutoff in
-- get_crew_live_positions() must not depend on each phone's clock.
create or replace function public.touch_live_position()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists live_positions_touch on public.live_positions;
create trigger live_positions_touch
  before insert or update on public.live_positions
  for each row execute function public.touch_live_position();

alter table public.crews enable row level security;
alter table public.crew_members enable row level security;
alter table public.live_positions enable row level security;

-- A security-definer membership check, so the crew_members policy below
-- doesn't have to query crew_members from inside its own policy (which
-- Postgres rejects as infinite recursion).
create or replace function public.is_crew_member(target_crew_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.crew_members where crew_id = target_crew_id and user_id = auth.uid()
  );
$$;

grant execute on function public.is_crew_member(uuid) to authenticated;
revoke execute on function public.is_crew_member(uuid) from anon, public;

drop policy if exists "crews_select_member" on public.crews;
create policy "crews_select_member" on public.crews
  for select using (public.is_crew_member(id));

drop policy if exists "crew_members_select_member" on public.crew_members;
create policy "crew_members_select_member" on public.crew_members
  for select using (public.is_crew_member(crew_id));

-- Your own live position: write and clear it directly, never read anyone
-- else's (that's get_crew_live_positions()'s job).
drop policy if exists "live_positions_insert_own" on public.live_positions;
create policy "live_positions_insert_own" on public.live_positions
  for insert with check (auth.uid() = user_id);
drop policy if exists "live_positions_update_own" on public.live_positions;
create policy "live_positions_update_own" on public.live_positions
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "live_positions_delete_own" on public.live_positions;
create policy "live_positions_delete_own" on public.live_positions
  for delete using (auth.uid() = user_id);
-- PostgREST's upsert needs to see the existing row to resolve the
-- conflict, so allow selecting your own row (and only your own).
drop policy if exists "live_positions_select_own" on public.live_positions;
create policy "live_positions_select_own" on public.live_positions
  for select using (auth.uid() = user_id);


create or replace function public.create_crew(crew_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  new_id uuid;
begin
  if me is null then
    raise exception 'not signed in';
  end if;
  insert into public.crews (name, owner_id) values (trim(crew_name), me) returning id into new_id;
  insert into public.crew_members (crew_id, user_id) values (new_id, me);
  return new_id;
end;
$$;

grant execute on function public.create_crew(text) to authenticated;
revoke execute on function public.create_crew(text) from anon, public;


-- Adds one of your accepted friends to a crew you're in. Returns what
-- happened so the UI can say something accurate.
create or replace function public.add_crew_member(target_crew_id uuid, member_user_id uuid)
returns text -- 'added' | 'already_member' | 'not_friends' | 'not_member'
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if not exists (select 1 from public.crew_members where crew_id = target_crew_id and user_id = me) then
    return 'not_member';
  end if;
  if not exists (
    select 1 from public.friendships
    where status = 'accepted'
      and ((requester_id = me and addressee_id = member_user_id)
        or (requester_id = member_user_id and addressee_id = me))
  ) then
    return 'not_friends';
  end if;
  if exists (select 1 from public.crew_members where crew_id = target_crew_id and user_id = member_user_id) then
    return 'already_member';
  end if;
  insert into public.crew_members (crew_id, user_id) values (target_crew_id, member_user_id);
  return 'added';
end;
$$;

grant execute on function public.add_crew_member(uuid, uuid) to authenticated;
revoke execute on function public.add_crew_member(uuid, uuid) from anon, public;


-- Owner-only: removes someone else from the crew.
create or replace function public.remove_crew_member(target_crew_id uuid, member_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.crew_members cm
    using public.crews c
    where cm.crew_id = target_crew_id
      and cm.user_id = member_user_id
      and c.id = cm.crew_id
      and c.owner_id = auth.uid()
      and member_user_id <> auth.uid();
end;
$$;

grant execute on function public.remove_crew_member(uuid, uuid) to authenticated;
revoke execute on function public.remove_crew_member(uuid, uuid) from anon, public;


-- Leave a crew. The last one out deletes it; an owner leaving hands the
-- crew to whoever has been in it longest.
create or replace function public.leave_crew(target_crew_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  successor uuid;
begin
  delete from public.crew_members where crew_id = target_crew_id and user_id = me;
  if not found then
    return;
  end if;
  select user_id into successor from public.crew_members
    where crew_id = target_crew_id order by joined_at limit 1;
  if successor is null then
    delete from public.crews where id = target_crew_id;
  else
    update public.crews set owner_id = successor where id = target_crew_id and owner_id = me;
  end if;
end;
$$;

grant execute on function public.leave_crew(uuid) to authenticated;
revoke execute on function public.leave_crew(uuid) from anon, public;


create or replace function public.rename_crew(target_crew_id uuid, crew_name text)
returns void
language sql
security definer
set search_path = public
as $$
  update public.crews set name = trim(crew_name) where id = target_crew_id and owner_id = auth.uid();
$$;

grant execute on function public.rename_crew(uuid, text) to authenticated;
revoke execute on function public.rename_crew(uuid, text) from anon, public;


-- What *you* share with one crew.
create or replace function public.set_crew_sharing(
  target_crew_id uuid,
  location_on boolean,
  speed_on boolean,
  lean_on boolean
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.crew_members
    set share_location = location_on, share_speed = speed_on, share_lean = lean_on
    where crew_id = target_crew_id and user_id = auth.uid();
$$;

grant execute on function public.set_crew_sharing(uuid, boolean, boolean, boolean) to authenticated;
revoke execute on function public.set_crew_sharing(uuid, boolean, boolean, boolean) from anon, public;


-- Your crews, with your own sharing settings for each.
create or replace function public.get_my_crews()
returns table (
  crew_id uuid,
  name text,
  owner_id uuid,
  member_count integer,
  share_location boolean,
  share_speed boolean,
  share_lean boolean
)
language sql
security definer
set search_path = public
as $$
  select c.id, c.name, c.owner_id,
    (select count(*)::integer from public.crew_members m where m.crew_id = c.id),
    me.share_location, me.share_speed, me.share_lean
  from public.crews c
  join public.crew_members me on me.crew_id = c.id and me.user_id = auth.uid()
  order by c.name;
$$;

grant execute on function public.get_my_crews() to authenticated;
revoke execute on function public.get_my_crews() from anon, public;


create or replace function public.get_crew_members(target_crew_id uuid)
returns table (user_id uuid, display_name text, is_owner boolean, share_location boolean)
language sql
security definer
set search_path = public
as $$
  select m.user_id, coalesce(nullif(p.display_name, ''), 'Unnamed rider'), m.user_id = c.owner_id, m.share_location
  from public.crew_members m
  join public.crews c on c.id = m.crew_id
  left join public.profiles p on p.user_id = m.user_id
  where m.crew_id = target_crew_id and public.is_crew_member(target_crew_id)
  order by (m.user_id = c.owner_id) desc, p.display_name;
$$;

grant execute on function public.get_crew_members(uuid) to authenticated;
revoke execute on function public.get_crew_members(uuid) from anon, public;


-- Everyone who shares a crew with you and is currently broadcasting,
-- filtered by *their* sharing flags for the crews you have in common:
-- a rider who shares location with crew A but not crew B is visible to
-- you only if you're in A. Speed/lean come back null unless they share
-- those with at least one of those crews. Anything older than 2 minutes
-- is treated as "not riding right now" and dropped.
create or replace function public.get_crew_live_positions()
returns table (
  user_id uuid,
  display_name text,
  crew_names text,
  latitude double precision,
  longitude double precision,
  speed_kph double precision,
  lean_deg double precision,
  heading_deg double precision,
  updated_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  with shared as (
    select them.user_id,
      string_agg(distinct c.name, ', ') as crew_names,
      bool_or(them.share_speed) as share_speed,
      bool_or(them.share_lean) as share_lean
    from public.crew_members mine
    join public.crew_members them on them.crew_id = mine.crew_id and them.user_id <> mine.user_id
    join public.crews c on c.id = mine.crew_id
    where mine.user_id = auth.uid() and them.share_location
    group by them.user_id
  )
  select lp.user_id,
    coalesce(nullif(p.display_name, ''), 'Unnamed rider'),
    s.crew_names,
    lp.latitude,
    lp.longitude,
    case when s.share_speed then lp.speed_kph end,
    case when s.share_lean then lp.lean_deg end,
    lp.heading_deg,
    lp.updated_at
  from shared s
  join public.live_positions lp on lp.user_id = s.user_id
  left join public.profiles p on p.user_id = s.user_id
  where lp.updated_at > now() - interval '2 minutes';
$$;

grant execute on function public.get_crew_live_positions() to authenticated;
revoke execute on function public.get_crew_live_positions() from anon, public;
