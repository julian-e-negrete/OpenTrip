-- Territory + trophies tables, and the leaderboard function.
-- Run this once in the SQL Editor, after schema.sql. See
-- docs/CLOUD_SYNC_SETUP.md.
--
-- Why a function instead of a view: every other table in this project
-- (schema.sql) has row-level security scoped to auth.uid() — a user can
-- only ever SELECT their own rows, full stop. A leaderboard fundamentally
-- needs to show *other* people's aggregate numbers, which a plain view
-- can't do — Postgres views don't bypass the underlying tables' RLS just
-- because the view itself is public (auth.uid() is resolved per-request
-- from the caller's JWT regardless of who owns the view). A
-- `security definer` function run by a sufficiently privileged owner
-- (the SQL Editor's role) does bypass RLS on the tables it reads —
-- that's the standard, documented Supabase pattern for "expose an
-- aggregate without exposing the private rows behind it." This function
-- only ever returns already-aggregated numbers (sums/counts/max) plus a
-- display name — never a raw trip, route, or vehicle.

create table if not exists public.territory_cells (
  user_id uuid not null references auth.users(id) on delete cascade,
  cell_key text not null,
  first_seen_at timestamptz not null default now(),
  -- How many trips have passed through this cell — drives the
  -- territory map's heat intensity (gamification/territory_map_screen.dart):
  -- a cell you've ridden through once glows faint, one you cross on every
  -- commute glows solid. Incremented locally on every revisit
  -- (data/repositories/gamification_repository.dart), then pushed as an
  -- overwrite (not a server-side increment) since the local count is
  -- already the authoritative cumulative total.
  visit_count integer not null default 1,
  primary key (user_id, cell_key)
);

-- Safe to re-run on a project that already had this table before this
-- column existed.
alter table public.territory_cells add column if not exists visit_count integer not null default 1;

alter table public.territory_cells enable row level security;

create policy "territory_cells_select_own" on public.territory_cells
  for select using (auth.uid() = user_id);
create policy "territory_cells_insert_own" on public.territory_cells
  for insert with check (auth.uid() = user_id);
-- A revisited cell's visit_count push (sync/sync_service.dart) is an
-- upsert — once a cell already exists remotely, bumping its count is an
-- UPDATE, not an INSERT, so this needs its own policy alongside the two
-- above. Postgres has no `create policy if not exists`, so drop-then-
-- create is what makes this safe to re-run.
drop policy if exists "territory_cells_update_own" on public.territory_cells;
create policy "territory_cells_update_own" on public.territory_cells
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);


create table if not exists public.trophies (
  user_id uuid not null references auth.users(id) on delete cascade,
  trophy_key text not null,
  earned_at timestamptz not null default now(),
  primary key (user_id, trophy_key)
);

alter table public.trophies enable row level security;

create policy "trophies_select_own" on public.trophies
  for select using (auth.uid() = user_id);
create policy "trophies_insert_own" on public.trophies
  for insert with check (auth.uid() = user_id);


-- Re-running this after best_0_60_seconds/best_100_180_seconds/
-- top_speed_kph were added to the returned columns needs the drop first
-- — Postgres won't let create-or-replace change an existing function's
-- return-row shape (same reason get_territory_map() below already needs
-- this).
drop function if exists public.get_leaderboard();
create function public.get_leaderboard()
returns table (
  user_id uuid,
  display_name text,
  total_distance_meters double precision,
  longest_drive_meters double precision,
  territory_cells integer,
  trophy_count integer,
  -- Racing stats (apps/mobile/lib/trip/accel_run_tracker.dart) — best
  -- (lowest) 0-60/100-180 km/h time across this rider's trips, and their
  -- highest-ever recorded top speed (GPS or BLE, whichever was higher on
  -- a given trip). Null until a trip actually crosses that bracket.
  best_0_60_seconds double precision,
  best_100_180_seconds double precision,
  top_speed_kph double precision
)
language sql
security definer
set search_path = public
as $$
  select
    p.user_id,
    coalesce(nullif(p.display_name, ''), 'Unnamed rider') as display_name,
    coalesce(t.total_distance, 0) as total_distance_meters,
    coalesce(t.longest_drive, 0) as longest_drive_meters,
    coalesce(tc.cell_count, 0) as territory_cells,
    coalesce(tr.trophy_count, 0) as trophy_count,
    t.best_0_60_seconds,
    t.best_100_180_seconds,
    t.top_speed_kph
  from public.profiles p
  left join (
    select
      user_id,
      sum(distance_meters) as total_distance,
      max(distance_meters) as longest_drive,
      min(best_0_60_seconds) as best_0_60_seconds,
      min(best_100_180_seconds) as best_100_180_seconds,
      max(greatest(coalesce(max_speed_kph, 0), coalesce(ble_max_speed_kph, 0))) as top_speed_kph
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
  -- profiles.leaderboard_visible (schema.sql) — a rider who's opted out
  -- of rankings via the Account tab's privacy toggle is excluded from
  -- every ranking view, this one included. See that column's comment.
  where coalesce(p.leaderboard_visible, true);
$$;

-- Only signed-in app users can call this — not the public "anon" role.
-- Supabase grants EXECUTE on every new public-schema function to anon
-- and authenticated by default (via a per-project ALTER DEFAULT
-- PRIVILEGES rule); the explicit grant below doesn't undo that, so the
-- revoke is required too, not just belt-and-suspenders.
grant execute on function public.get_leaderboard() to authenticated;
revoke execute on function public.get_leaderboard() from anon, public;


-- Same "security definer to safely expose cross-user data" pattern as
-- get_leaderboard() above, but for the territory *map* (which cells,
-- whose) rather than a per-rider total. Deliberately returns only cell
-- keys + who owns them — never a raw trip route or timestamp, so this
-- can't be used to reconstruct anyone's actual path or figure out where
-- they live/work down to house-level precision (a cell is ~1.1km).
-- Returns every claimed cell with no viewport filtering — fine at this
-- app's current scale; if the territory map ever gets slow to load, the
-- fix is adding bounding-box parameters here, not filtering client-side
-- (that would still ship every row over the wire first).
-- Re-running this after visit_count was added to the returned columns
-- needs the drop first — Postgres won't let create-or-replace change an
-- existing function's return-row shape.
drop function if exists public.get_territory_map();
create function public.get_territory_map()
returns table (
  cell_key text,
  user_id uuid,
  display_name text,
  visit_count integer
)
language sql
security definer
set search_path = public
as $$
  select tc.cell_key, tc.user_id, coalesce(nullif(p.display_name, ''), 'Unnamed rider') as display_name,
    tc.visit_count
  from public.territory_cells tc
  join public.profiles p on p.user_id = tc.user_id
  where coalesce(p.leaderboard_visible, true);
$$;

grant execute on function public.get_territory_map() to authenticated;
revoke execute on function public.get_territory_map() from anon, public;
