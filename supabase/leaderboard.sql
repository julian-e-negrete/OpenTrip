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
  primary key (user_id, cell_key)
);

alter table public.territory_cells enable row level security;

create policy "territory_cells_select_own" on public.territory_cells
  for select using (auth.uid() = user_id);
create policy "territory_cells_insert_own" on public.territory_cells
  for insert with check (auth.uid() = user_id);


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


create or replace function public.get_leaderboard()
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
  select
    p.user_id,
    coalesce(nullif(p.display_name, ''), 'Unnamed rider') as display_name,
    coalesce(t.total_distance, 0) as total_distance_meters,
    coalesce(t.longest_drive, 0) as longest_drive_meters,
    coalesce(tc.cell_count, 0) as territory_cells,
    coalesce(tr.trophy_count, 0) as trophy_count
  from public.profiles p
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
  -- profiles.leaderboard_visible (schema.sql) — a rider who's opted out
  -- of rankings via the Account tab's privacy toggle is excluded from
  -- every ranking view, this one included. See that column's comment.
  where coalesce(p.leaderboard_visible, true);
$$;

-- Only signed-in app users can call this — not the public "anon" role.
grant execute on function public.get_leaderboard() to authenticated;


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
create or replace function public.get_territory_map()
returns table (
  cell_key text,
  user_id uuid,
  display_name text
)
language sql
security definer
set search_path = public
as $$
  select tc.cell_key, tc.user_id, coalesce(nullif(p.display_name, ''), 'Unnamed rider') as display_name
  from public.territory_cells tc
  join public.profiles p on p.user_id = tc.user_id
  where coalesce(p.leaderboard_visible, true);
$$;

grant execute on function public.get_territory_map() to authenticated;
