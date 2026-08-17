-- Friends: a lighter-weight ranking than the global leaderboard, plus the
-- lookup needed to actually find someone to add. Run this once in the SQL
-- Editor, after schema.sql and leaderboard.sql. See docs/CLOUD_SYNC_SETUP.md.
--
-- The friendships table itself only gets a SELECT policy — every write
-- (send a request, accept one, remove a friend) goes through one of the
-- functions below instead of a direct insert/update/delete. That's
-- deliberate: "did A already request B?", "does a reverse request from B
-- already exist and should this just accept it instead of creating a
-- second, contradictory row?" are exactly the kind of check-then-act
-- logic RLS's per-row `using`/`with check` clauses can't express — a
-- `security definer` function can, atomically, in one statement.
--
-- Every function below pairs its `grant ... to authenticated` with a
-- `revoke ... from anon` — Supabase grants EXECUTE on every new
-- public-schema function to anon and authenticated by default (a
-- per-project ALTER DEFAULT PRIVILEGES rule), so the explicit grant
-- alone doesn't stop an unauthenticated caller from reaching these.

create table if not exists public.friendships (
  requester_id uuid not null references auth.users(id) on delete cascade,
  addressee_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  primary key (requester_id, addressee_id),
  check (requester_id <> addressee_id)
);

alter table public.friendships enable row level security;

create policy "friendships_select_own" on public.friendships
  for select using (auth.uid() = requester_id or auth.uid() = addressee_id);


-- Finds riders by display name, to add as a friend. Never returns email
-- or anything beyond (user_id, display_name) — same "expose the minimum,
-- not the row" posture as get_leaderboard(). Excludes yourself.
create or replace function public.search_riders(query text)
returns table (user_id uuid, display_name text)
language sql
security definer
set search_path = public
as $$
  select p.user_id, coalesce(nullif(p.display_name, ''), 'Unnamed rider') as display_name
  from public.profiles p
  where p.user_id <> auth.uid()
    and p.display_name ilike '%' || query || '%'
  order by p.display_name
  limit 20;
$$;

grant execute on function public.search_riders(text) to authenticated;
revoke execute on function public.search_riders(text) from anon, public;


-- Sends a friend request — or, if the target already sent *you* one
-- (a pending row the other way round), accepts that instead of leaving
-- two contradictory pending rows sitting around. Returns what actually
-- happened so the UI can say something accurate rather than assuming.
create or replace function public.send_or_accept_friend_request(target_user_id uuid)
returns text -- 'requested' | 'accepted' | 'already_friends' | 'already_requested'
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  forward_status text;
  reverse_status text;
begin
  if me is null or me = target_user_id then
    raise exception 'invalid target';
  end if;

  select status into forward_status from public.friendships
    where requester_id = me and addressee_id = target_user_id;
  if found then
    return case when forward_status = 'accepted' then 'already_friends' else 'already_requested' end;
  end if;

  select status into reverse_status from public.friendships
    where requester_id = target_user_id and addressee_id = me;
  if found then
    if reverse_status = 'accepted' then
      return 'already_friends';
    end if;
    update public.friendships set status = 'accepted'
      where requester_id = target_user_id and addressee_id = me;
    return 'accepted';
  end if;

  insert into public.friendships (requester_id, addressee_id, status)
    values (me, target_user_id, 'pending');
  return 'requested';
end;
$$;

grant execute on function public.send_or_accept_friend_request(uuid) to authenticated;
revoke execute on function public.send_or_accept_friend_request(uuid) from anon, public;


-- Accepts an incoming request. A no-op (no error) if there's no such
-- pending request — e.g. it was already accepted or withdrawn — so a
-- stale UI button tap doesn't need special-case error handling.
create or replace function public.accept_friend_request(requester_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.friendships set status = 'accepted'
    where requester_id = requester_user_id and addressee_id = auth.uid() and status = 'pending';
end;
$$;

grant execute on function public.accept_friend_request(uuid) to authenticated;
revoke execute on function public.accept_friend_request(uuid) from anon, public;


-- Removes a friendship in either direction — also how you decline a
-- pending incoming request or cancel one you sent, since those are just
-- rows in the same table.
create or replace function public.remove_friendship(other_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.friendships
    where (requester_id = auth.uid() and addressee_id = other_user_id)
       or (requester_id = other_user_id and addressee_id = auth.uid());
end;
$$;

grant execute on function public.remove_friendship(uuid) to authenticated;
revoke execute on function public.remove_friendship(uuid) from anon, public;


-- Your accepted friends.
create or replace function public.get_friends()
returns table (user_id uuid, display_name text)
language sql
security definer
set search_path = public
as $$
  select p.user_id, coalesce(nullif(p.display_name, ''), 'Unnamed rider') as display_name
  from public.friendships f
  join public.profiles p
    on p.user_id = (case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end)
  where f.status = 'accepted' and (f.requester_id = auth.uid() or f.addressee_id = auth.uid())
  order by p.display_name;
$$;

grant execute on function public.get_friends() to authenticated;
revoke execute on function public.get_friends() from anon, public;


-- Requests sent *to* you, still pending your response.
create or replace function public.get_pending_friend_requests()
returns table (requester_id uuid, display_name text, requested_at timestamptz)
language sql
security definer
set search_path = public
as $$
  select f.requester_id, coalesce(nullif(p.display_name, ''), 'Unnamed rider') as display_name, f.created_at
  from public.friendships f
  join public.profiles p on p.user_id = f.requester_id
  where f.addressee_id = auth.uid() and f.status = 'pending'
  order by f.created_at desc;
$$;

grant execute on function public.get_pending_friend_requests() to authenticated;
revoke execute on function public.get_pending_friend_requests() from anon, public;


-- Same shape as get_leaderboard() (leaderboard.sql), scoped to you plus
-- your accepted friends instead of every rider. Respects
-- profiles.leaderboard_visible the same way get_leaderboard() does —
-- opting out of rankings means out of every ranking view, friends
-- included, not just the global one.
create or replace function public.get_friends_leaderboard()
returns table (
  user_id uuid,
  display_name text,
  total_distance_meters double precision,
  longest_drive_meters double precision,
  territory_cells integer,
  trophy_count integer
)
language sql
security definer
set search_path = public
as $$
  with friend_ids as (
    select case when requester_id = auth.uid() then addressee_id else requester_id end as friend_id
    from public.friendships
    where status = 'accepted' and (requester_id = auth.uid() or addressee_id = auth.uid())
    union
    select auth.uid()
  )
  select
    p.user_id,
    coalesce(nullif(p.display_name, ''), 'Unnamed rider') as display_name,
    coalesce(t.total_distance, 0) as total_distance_meters,
    coalesce(t.longest_drive, 0) as longest_drive_meters,
    coalesce(tc.cell_count, 0) as territory_cells,
    coalesce(tr.trophy_count, 0) as trophy_count
  from public.profiles p
  join friend_ids f on f.friend_id = p.user_id
  left join (
    select user_id, sum(distance_meters) as total_distance, max(distance_meters) as longest_drive
    from public.trips
    group by user_id
  ) t on t.user_id = p.user_id
  left join (
    select user_id, count(*) as cell_count
    from public.territory_cells
    group by user_id
  ) tc on tc.user_id = p.user_id
  left join (
    select user_id, count(*) as trophy_count
    from public.trophies
    group by user_id
  ) tr on tr.user_id = p.user_id
  where coalesce(p.leaderboard_visible, true);
$$;

grant execute on function public.get_friends_leaderboard() to authenticated;
revoke execute on function public.get_friends_leaderboard() from anon, public;


-- Same shape as get_territory_map() (leaderboard.sql), scoped to you
-- plus your accepted friends instead of every rider — the map-view
-- counterpart to get_friends_leaderboard() above. Same
-- leaderboard_visible + "never a raw route, just cell ownership"
-- posture as get_territory_map()'s own comment explains.
create or replace function public.get_friends_territory_map()
returns table (
  cell_key text,
  user_id uuid,
  display_name text
)
language sql
security definer
set search_path = public
as $$
  with friend_ids as (
    select case when requester_id = auth.uid() then addressee_id else requester_id end as friend_id
    from public.friendships
    where status = 'accepted' and (requester_id = auth.uid() or addressee_id = auth.uid())
    union
    select auth.uid()
  )
  select tc.cell_key, tc.user_id, coalesce(nullif(p.display_name, ''), 'Unnamed rider') as display_name
  from public.territory_cells tc
  join public.profiles p on p.user_id = tc.user_id
  join friend_ids f on f.friend_id = tc.user_id
  where coalesce(p.leaderboard_visible, true);
$$;

grant execute on function public.get_friends_territory_map() to authenticated;
revoke execute on function public.get_friends_territory_map() from anon, public;
