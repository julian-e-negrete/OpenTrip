# Setting up cloud sync

Cloud sync needs two things set up in your Supabase project that I can't
do myself without direct database credentials. Everything else (the app
code, the push/pull/live-sync logic) is already wired up and does nothing
harmful if you skip these — sync just fails quietly and your data stays
local-only, exactly like before.

## 1. Run the schema

1. Supabase Dashboard → your project → **SQL Editor** → **New query**.
2. Paste the contents of [`supabase/schema.sql`](../supabase/schema.sql)
   from this repo.
3. **Run**.

That creates four tables (`vehicles`, `trips`, `trip_points`, `profiles`),
each with row-level security scoped to `auth.uid()` — a user can only
ever read/write their own rows, enforced by Postgres itself, not just app
code.

**Already ran this before `profiles.country_code`,
`profiles.leaderboard_visible`, `trips.behavior_*`,
`trips.phone_lean_max_deg`, `trips.ble_odometer_km`,
`trip_points.ble_*`, `trip_music_events`, or
`vehicles.starting_odometer_km`/`service_interval_km`/
`last_service_odometer_km` existed?** Just re-run the current
`schema.sql` — every statement in it, including all of these
tables/columns, is safe to run again (`create table if not exists`,
`add column if not exists`).

## 2. Enable Realtime (for continuous, not on-demand, sync)

1. Same SQL Editor, another **New query**.
2. Paste [`supabase/enable_realtime.sql`](../supabase/enable_realtime.sql).
3. **Run**.

This adds `vehicles`, `trips`, and `profiles` to Supabase's Realtime
publication — Postgres's logical replication feed, pushed to the app over
a websocket. Without this step, sync still works, but only "pull once at
sign-in + push after each local change" (see `sync/sync_service.dart`'s
doc comment) — a change made on a second device wouldn't show up on the
first until you sign in again or tap "Sync now." With it, a change on one
device reaches every other signed-in device in about a second, no action
needed.

## 3. Enable the leaderboard

1. Same SQL Editor, another **New query**.
2. Paste [`supabase/leaderboard.sql`](../supabase/leaderboard.sql).
3. **Run**.

Creates `territory_cells` and `trophies` (same per-user RLS as everything
else), plus `get_leaderboard()` and `get_territory_map()` functions.
Those are the exception to "every table only shows you your own rows" —
see the comment at the top of `leaderboard.sql` for why `security
definer` functions, not views, were necessary to show cross-user data at
all without a plain view accidentally exposing raw private rows.
`get_leaderboard()` only ever returns already-aggregated numbers
(sums/counts) and a display name; `get_territory_map()` only returns
which grid cell each rider has claimed and by whom, never a raw trip
route. Skipping this step just means the Leaderboard screen shows "no
data yet" and the territory map (the map icon on that screen) shows
nothing — nothing else is affected.

**Already ran `leaderboard.sql` before `get_territory_map()` existed,
before step 1's `leaderboard_visible` column existed, or before
`territory_cells.visit_count` existed?** Just re-run the current file —
every statement in it is safe to run again (`create table if not
exists`, `drop function if exists` + `create function`, `add column if
not exists`).

**Already ran an earlier version of this file (or `friends.sql`) before
they revoked `anon` execute access?** Definitely re-run both — Supabase
grants `EXECUTE` on every new function to the unauthenticated `anon`
role by default, and the earlier versions of these files only granted
to `authenticated` without revoking that default, so `get_leaderboard()`
and friends' functions were callable without signing in (still only
ever returning the same aggregated, non-sensitive data the app itself
shows — but callable directly against the REST API by anyone with your
project URL regardless). Re-running the current files closes that.

## 4. Enable friends

1. Same SQL Editor, another **New query**.
2. Paste [`supabase/friends.sql`](../supabase/friends.sql).
3. **Run**.

Creates `friendships` (a request/accept model — see the comment at the
top of `friends.sql` for why every write to it goes through a function
rather than a direct insert/update/delete) plus the functions the
Friends screen needs: searching for a rider by name, sending/accepting/
removing a friendship, `get_friends_leaderboard()` — the same shape as
`get_leaderboard()`, scoped to you and your accepted friends — and
`get_friends_territory_map()`, the same relationship to
`get_territory_map()`. Skipping this step means the people icon on the
Leaderboard screen still opens, but search and every list on it (and
the Map tab's "Friends" toggle) come back empty.

**Already ran `friends.sql` before `get_friends_territory_map()`
existed, before every function in it revoked `anon` execute access, or
before it returned `visit_count`?** Re-run the current file — every
statement is safe to run again, and the `anon` revoke matters: Supabase grants `EXECUTE` on new functions to the
unauthenticated `anon` role by default (sometimes via an explicit grant,
sometimes via the `public` pseudo-role — both got closed here), so an
earlier run of this file may have left these callable without signing
in. They only ever return the same aggregated, non-sensitive data the
app itself shows once signed in, but re-running closes the gap regardless.

## 5. That's it

No new dart-defines, no new secrets. The app already has everything it
needs (the same `SUPABASE_URL`/`SUPABASE_ANON_KEY` used for login).

## What doesn't sync (yet)

- **Photos** (vehicle photos, your avatar) — these are local file paths.
  Syncing them needs a Supabase Storage bucket and its own policies,
  which is a separate piece of setup not included here.
- **Trip points aren't part of the live feed.** A finished trip can push
  hundreds of GPS points in one go, which isn't a good fit for individual
  realtime events on every other device. They stay on a lazy pull —
  fetched the first time you open that trip's detail screen on a device
  that doesn't have them locally yet (see `TripRepository.pointsForTrip`).
- **Conflict resolution** — if the same row is somehow edited on two
  devices at nearly the same moment, whichever write lands last on the
  server simply overwrites the other. No per-field merge. Unlikely to
  matter for one person's own vehicles/trips, but worth knowing.
- **Deleting a vehicle while offline** removes it locally immediately,
  and the remote delete is attempted best-effort — if that fails (no
  network), the remote copy can resurrect on your next pull/live update.
  Deleting again once you're back online clears it for good.

See `docs/ROADMAP.md` for what's still open around this.
