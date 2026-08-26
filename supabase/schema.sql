-- OpenTrip cloud sync schema.
--
-- Run this once in your Supabase project's SQL Editor (Dashboard ->
-- SQL Editor -> New query -> paste -> Run). See docs/CLOUD_SYNC_SETUP.md.
--
-- Mirrors the local SQLite schema in apps/mobile/lib/data/local_database.dart
-- as closely as possible on purpose, so sync/local logic (apps/mobile/lib/sync/)
-- doesn't need to translate between two different shapes. IDs are the same
-- UUIDs the app already generates locally (see the `uuid` package usage in
-- data/repositories/*.dart) — no ID remapping between local and remote.
--
-- Every table is scoped to auth.uid() via row-level security, so this only
-- ever works for a real signed-in user — guest-mode data (see
-- auth/current_user.dart) has no Supabase session to authenticate the
-- write with, and stays local-only. That's intentional, not a bug.

create table if not exists public.vehicles (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  type text not null,
  brand text not null default '',
  model text not null default '',
  ble_connector text not null default 'none',
  created_at timestamptz not null default now(),
  -- Mileage/service tracking (apps/mobile/lib/vehicles/vehicle_detail_screen.dart)
  -- — see data/models/vehicle.dart's field comments for what null means
  -- on each of these.
  starting_odometer_km double precision,
  service_interval_km double precision,
  last_service_odometer_km double precision,
  updated_at timestamptz not null default now()
);

-- Safe to re-run on a project that already had this table before these
-- columns existed.
alter table public.vehicles add column if not exists starting_odometer_km double precision;
alter table public.vehicles add column if not exists service_interval_km double precision;
alter table public.vehicles add column if not exists last_service_odometer_km double precision;

alter table public.vehicles enable row level security;

create policy "vehicles_select_own" on public.vehicles
  for select using (auth.uid() = user_id);
create policy "vehicles_insert_own" on public.vehicles
  for insert with check (auth.uid() = user_id);
create policy "vehicles_update_own" on public.vehicles
  for update using (auth.uid() = user_id);
create policy "vehicles_delete_own" on public.vehicles
  for delete using (auth.uid() = user_id);


create table if not exists public.trips (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  started_at timestamptz not null,
  ended_at timestamptz,
  distance_meters double precision not null default 0,
  duration_seconds integer not null default 0,
  avg_speed_kph double precision,
  max_speed_kph double precision,
  point_count integer not null default 0,
  ble_max_speed_kph double precision,
  ble_max_rpm integer,
  ble_max_lean_deg double precision,
  ble_max_brake_kpa double precision,
  ble_min_water_temp_c integer,
  ble_max_water_temp_c integer,
  -- GPS-derived driving-behavior stats (apps/mobile/lib/trip/driving_math.dart)
  -- — available for every trip, not just BLE-equipped vehicles.
  behavior_max_accel_g double precision,
  behavior_max_brake_g double precision,
  behavior_max_cornering_g double precision,
  behavior_hard_accel_count integer,
  behavior_hard_brake_count integer,
  behavior_hard_cornering_count integer,
  -- Phone-accelerometer max lean angle (apps/mobile/lib/trip/lean_angle_tracker.dart)
  -- — opt-in per recording, independent of ble_max_lean_deg above (two
  -- different sensors; a BLE-connected bike can have both).
  phone_lean_max_deg double precision,
  -- The bike's own odometer reading (Kawasaki Rideology's "MC info"
  -- frame) at the last telemetry frame received during this trip — see
  -- data/models/trip.dart's field comment. Not a max/min like the ble_*
  -- columns above; an odometer only ever counts up.
  ble_odometer_km double precision,
  updated_at timestamptz not null default now()
);

-- Safe to re-run on a project that already had this table before these
-- columns existed.
alter table public.trips add column if not exists behavior_max_accel_g double precision;
alter table public.trips add column if not exists behavior_max_brake_g double precision;
alter table public.trips add column if not exists behavior_max_cornering_g double precision;
alter table public.trips add column if not exists behavior_hard_accel_count integer;
alter table public.trips add column if not exists behavior_hard_brake_count integer;
alter table public.trips add column if not exists behavior_hard_cornering_count integer;
alter table public.trips add column if not exists phone_lean_max_deg double precision;
alter table public.trips add column if not exists ble_odometer_km double precision;

alter table public.trips enable row level security;

create policy "trips_select_own" on public.trips
  for select using (auth.uid() = user_id);
create policy "trips_insert_own" on public.trips
  for insert with check (auth.uid() = user_id);
create policy "trips_update_own" on public.trips
  for update using (auth.uid() = user_id);
create policy "trips_delete_own" on public.trips
  for delete using (auth.uid() = user_id);


-- Route points. Pushed in bulk once a trip finishes (see sync/sync_service.dart)
-- rather than per-GPS-fix — recording itself never needs network. Pulled
-- lazily per-trip (trip detail screen) rather than eagerly for every trip,
-- since this table can get large fast.
create table if not exists public.trip_points (
  trip_id uuid not null references public.trips(id) on delete cascade,
  seq integer not null,
  latitude double precision not null,
  longitude double precision not null,
  altitude_meters double precision,
  speed_kph double precision,
  "timestamp" timestamptz not null,
  -- Vehicle-reported (BLE) telemetry at this exact GPS fix — see
  -- data/models/trip_point.dart's field comment. Powers
  -- trip_detail_screen.dart's route-replay instrument HUD.
  ble_speed_kph double precision,
  ble_rpm integer,
  ble_gear integer,
  ble_throttle_percent double precision,
  ble_lean_deg double precision,
  ble_water_temp_c integer,
  primary key (trip_id, seq)
);

-- Safe to re-run on a project that already had this table before these
-- columns existed.
alter table public.trip_points add column if not exists ble_speed_kph double precision;
alter table public.trip_points add column if not exists ble_rpm integer;
alter table public.trip_points add column if not exists ble_gear integer;
alter table public.trip_points add column if not exists ble_throttle_percent double precision;
alter table public.trip_points add column if not exists ble_lean_deg double precision;
alter table public.trip_points add column if not exists ble_water_temp_c integer;

alter table public.trip_points enable row level security;

create policy "trip_points_select_own" on public.trip_points
  for select using (
    exists (select 1 from public.trips t where t.id = trip_points.trip_id and t.user_id = auth.uid())
  );
create policy "trip_points_insert_own" on public.trip_points
  for insert with check (
    exists (select 1 from public.trips t where t.id = trip_points.trip_id and t.user_id = auth.uid())
  );
create policy "trip_points_delete_own" on public.trip_points
  for delete using (
    exists (select 1 from public.trips t where t.id = trip_points.trip_id and t.user_id = auth.uid())
  );


-- One row per track change during a trip, captured from Spotify's own
-- local "now playing" broadcast on-device (see
-- apps/mobile/lib/trip/spotify_now_playing.dart) — not Spotify's Web
-- API, so no OAuth token or third-party-app user cap involved on
-- Spotify's side; this table is just where OpenTrip stores what it
-- already received. Same "pushed in bulk once the trip finishes, pulled
-- lazily per-trip" shape as trip_points, just far lower volume (tens of
-- rows per trip, not hundreds).
create table if not exists public.trip_music_events (
  trip_id uuid not null references public.trips(id) on delete cascade,
  seq integer not null,
  track text not null,
  artist text,
  album text,
  spotify_uri text,
  started_at timestamptz not null,
  primary key (trip_id, seq)
);

alter table public.trip_music_events enable row level security;

create policy "trip_music_events_select_own" on public.trip_music_events
  for select using (
    exists (select 1 from public.trips t where t.id = trip_music_events.trip_id and t.user_id = auth.uid())
  );
create policy "trip_music_events_insert_own" on public.trip_music_events
  for insert with check (
    exists (select 1 from public.trips t where t.id = trip_music_events.trip_id and t.user_id = auth.uid())
  );
create policy "trip_music_events_delete_own" on public.trip_music_events
  for delete using (
    exists (select 1 from public.trips t where t.id = trip_music_events.trip_id and t.user_id = auth.uid())
  );


-- Display name + country for now — avatar/vehicle photo sync needs
-- Supabase Storage (a bucket + its own policies), not set up yet.
-- country_code is a picked ISO 3166-1 alpha-2 code (see
-- apps/mobile/lib/data/catalog/country_catalog.dart), captured now so
-- it's there to slice a future leaderboard by if that's ever built —
-- RLS below still means only its own owner can read it until/unless a
-- security-definer function (like get_leaderboard()) deliberately
-- exposes it, the same pattern supabase/leaderboard.sql already uses.
-- leaderboard_visible is that opt-out: get_leaderboard(),
-- get_territory_map(), and get_friends_leaderboard() (leaderboard.sql,
-- friends.sql) all exclude a profile with this set to false, so signing
-- in and syncing no longer has to mean being ranked.
create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  country_code text,
  leaderboard_visible boolean not null default true,
  updated_at timestamptz not null default now()
);

-- Safe to re-run on a project that already had this table before these
-- columns existed.
alter table public.profiles add column if not exists country_code text;
alter table public.profiles add column if not exists leaderboard_visible boolean not null default true;

alter table public.profiles enable row level security;

create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = user_id);
create policy "profiles_insert_own" on public.profiles
  for insert with check (auth.uid() = user_id);
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = user_id);
