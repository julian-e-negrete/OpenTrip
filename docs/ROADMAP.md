# Roadmap

## Done

- **Kawasaki Rideology BLE connector** (`packages/kawasaki_rideology_ble/`):
  protocol constants, frame builder, byte-level parsers for the frames a
  trip tracker actually needs (live telemetry, odometer/trip, temps),
  startup-handshake orchestration, and golden-fixture tests ported from
  real captured frames. **Confirmed working against a real 2026 Z500 ABS**
  — see `README.md`'s validation section.
- **Flutter app + platform scaffolding** (`apps/mobile/`): real `android/`
  (built and installable) and `ios/` (scaffolded, unbuildable without a
  Mac) projects, wired to the BLE connector via `flutter_blue_plus`, plus
  an in-app BLE log viewer (`screens/log_screen.dart`) with one-tap
  copy-to-clipboard for pulling logs off a phone with no computer.
- **Auth** (`auth/`): Google sign-in (native ID-token flow) and
  passwordless email (6-digit OTP, no deep-linking needed) via Supabase
  Auth, plus a local guest mode (`auth/current_user.dart`) so every
  on-device feature works with zero backend setup — login is an optional
  upgrade path, not a gate. Confirmed working end-to-end against a real
  Supabase project, including tracking down a `DEVELOPER_ERROR (10)`
  
  Google Sign-In failure to ephemeral CI runners auto-generating a fresh
  debug-signing keystore on every run — fixed by pinning one
  (`android/app/debug.keystore`, deliberately committed; see
  `docs/AUTH_SETUP.md`). See that doc for the (unavoidable,
  you-bring-your-own-project) setup steps.
- **Multi-vehicle trip recording** (`data/`, `trip/`, `vehicles/`,
  `trips/`): on-device SQLite (vehicles / trips / trip_points tables,
  scoped per signed-in user), a vehicle CRUD screen, a GPS recorder
  (`trip/location_recorder.dart` — haversine distance, GPS-glitch
  rejection, accuracy filtering) with a live start/stop recording screen,
  and trip history + detail views.
- **BLE telemetry wired into trip recording** (`vehicle/kawasaki_connector.dart`,
  `trip/recording_screen.dart`): the scan/connect/handshake logic that used
  to live only in the standalone BLE demo screen is now a shared helper.
  Recording a trip on a vehicle flagged `kawasakiRideology` shows an
  optional "Connect bike" card; if connected, live telemetry
  (speed/RPM/lean/front-brake-pressure/water-temp) is tracked for max/min
  values alongside GPS and saved onto the trip (`data/models/trip.dart`'s
  `ble*` fields), shown in trip detail under "From the bike". A trip
  without a bike connection, or on a non-BLE vehicle, is unaffected —
  every `ble*` field just stays null.
- **Catalog-driven vehicle creation** (`data/catalog/vehicle_catalog.dart`,
  `vehicles/add_vehicle_screen.dart`): adding a car or motorcycle is now
  brand -> model, not free text — a curated (not exhaustive) starting
  catalog where a model can carry a known `VehicleBleConnector`, so
  picking "Kawasaki" + "Z500 ABS" auto-wires the same connector this app
  ships, no manual checkbox. Adding a future connector (CFMoto, another
  Kawasaki model, etc.) means adding catalog entries, not touching the
  creation UI. An "Other / not listed" escape hatch keeps free text
  available for anything not in the catalog (with no connector).
  Bicycle/other vehicle types skip the catalog entirely. Vehicles and
  user profiles can now carry a locally-stored photo
  (`data/local_image_store.dart`).
- **Account tab** (`account/account_screen.dart`): editable display
  name + avatar (never the email — that's stored but deliberately not
  shown, since a display name is what's meant to identify you to other
  users once social features exist), vehicle/trip/distance counts, and
  "Delete account". That wipes both local and (if synced) cloud data —
  it still can't delete the actual Supabase auth account/email
  registration itself, since that needs a privileged service-role
  operation (an Edge Function) a mobile client's anon key can't perform;
  the confirmation dialog says so explicitly.
- **Cloud sync — continuous, not on-demand** (`sync/sync_service.dart`,
  `supabase/schema.sql`, `supabase/enable_realtime.sql`): vehicles,
  trips, trip points, and profile display name sync to Supabase Postgres
  for real signed-in accounts. Three layers: push after every local
  write; a catch-up pull right after sign-in (including an already-active
  session on cold app start); and a live Postgres Changes (Realtime)
  websocket subscription on vehicles/trips/profiles for as long as the
  app is running signed in, so a change on one device reaches every other
  signed-in device in about a second with no button or reconnect needed.
  A manual "Sync now" button remains for forcing a pass or checking
  status. Trip points deliberately stay off the live feed (a finished
  trip can push hundreds of point rows at once — not a good fit for
  per-row realtime events) and use the pre-existing lazy pull-per-trip
  instead. Guest-mode data stays local-only on purpose (no `auth.uid()`
  session to authenticate a sync write with, and RLS would reject it
  anyway). Needs two one-time setup steps only the project owner can do
  — running `supabase/schema.sql` then `supabase/enable_realtime.sql` in
  the Supabase SQL Editor — see `docs/CLOUD_SYNC_SETUP.md`; sync still
  works without the second step, just falls back to pull-at-sign-in
  only. Still not a full offline-sync engine: last-write-wins (no
  per-field conflict merge), and vehicle/profile **photos don't sync yet**
  (needs a Supabase Storage bucket, separate setup not included here).
- **Background recording + BLE** (`trip/location_recorder.dart`): one
  change covers what were two separate roadmap items, since they shared a
  root cause — Android killing the app process when backgrounded, which
  drops both the GPS stream and the BLE connection together (same
  process). Fixed via geolocator's built-in Android foreground-service
  integration (`AndroidSettings.foregroundNotificationConfig`) rather
  than a separate background-service plugin/isolate: a persistent
  notification keeps the process alive while recording, so both GPS and
  the Kawasaki BLE connection survive backgrounding with no other code
  change needed. Deliberately doesn't request
  `ACCESS_BACKGROUND_LOCATION` — a foreground service already keeps
  Android treating the app as foregrounded for location purposes, which
  is both less permission friction and avoids Play Store's
  background-location review requirement. iOS gets the equivalent
  `AppleSettings`/`Info.plist` config for parity, but is unverified —
  this project has no way to build/run iOS (needs a Mac). Needed
  `POST_NOTIFICATIONS` (Android 13+) to actually work — missing it broke
  GPS the moment the screen locked while leaving BLE unaffected (an
  unrelated subsystem), which is exactly what surfaced this in testing;
  fixed by declaring + requesting that permission
  (`LocationRecorder.ensureReady()`).
  **Known limit, accepted deliberately rather than built around:**
  survives screen lock and switching to another app, but not the user
  explicitly swiping this app away from the Recents/app-switcher list —
  Android kills the service by default when its task is removed, and
  `geolocator`'s bundled foreground service (confirmed by reading its
  source: no `stopWithTask="false"`, no `onTaskRemoved()` override) does
  nothing to prevent that. Matching Google Maps' full swipe-away
  resilience would mean swapping to a dedicated background-service
  plugin (`flutter_foreground_task`) running the recording/BLE logic in
  a separate isolate — real architecture work, not a config flag —
  intentionally not done now.
- **Maps** (`trips/trip_detail_screen.dart`): route polyline + start/end
  markers over OpenStreetMap tiles, via `flutter_map` (pure-Dart canvas
  renderer) rather than MapLibre GL — no native map SDK, no platform
  channels, meaningfully less build risk for the same result. Uses the
  public `tile.openstreetmap.org` server, fine at this app's current
  scale but subject to OSM's tile usage policy (not for heavy/production
  traffic); self-hosting tiles or a paid provider (Stadia Maps, MapTiler,
  Thunderforest) is the documented upgrade path if that ever matters.
- **Territory/leaderboard/trophies** (`gamification/`, `leaderboard/`,
  `supabase/leaderboard.sql`): mirrors TripRank's four ranked categories
  (distance, longest drive, territory explored, trophies) — deliberately
  *not* speed-based. Territory is a simple visited-grid-cell count
  (`gamification/territory.dart` — ~1.1km cells, not equal-area, a
  deliberate simplification for a bragging-rights stat, not a GIS tool);
  trophies are a small, extensible, condition-based catalog
  (`gamification/trophies.dart`) re-evaluated after every finished trip,
  with a dialog celebrating anything newly earned. The leaderboard itself
  needed a new kind of Supabase object: every other table's RLS means a
  user can only ever see their own rows, so cross-user rankings needed a
  `security definer` Postgres function (the standard pattern for
  "expose an aggregate without exposing the private rows behind it") —
  see `supabase/leaderboard.sql`'s comment. Reachable via a leaderboard
  icon on the Trips tab; guests see a "sign in to compare" message
  instead, since there's no account to rank.

## Not done yet

1. **Photo sync.** Vehicle/profile photos are local-only — see "Cloud
   sync" above. Needs a Supabase Storage bucket + policies.

## Explicitly deferred inside the Kawasaki connector itself

See `packages/kawasaki_rideology_ble/README.md`'s "What's implemented"
table — vehicle tuning/settings (0x47/0x48), maintenance-due dates
(0x1E), and suspension/IMU data (0x4B) are documented upstream but not
ported, because they're not needed for trip tracking and would just be
unused surface area to maintain. Contributions welcome if someone wants
them for a different purpose (e.g. a full Rideology-app replacement
rather than a trip-tracker enrichment source).

## Second vehicle-connector candidate

CFMoto/Voge/Zontes/Benelli/QJ Motor/Moto Morini share a dash-mirroring
protocol (MotoPlay/EasyConnect) already reimplemented independently by
the `open-cfmoto` project. That one is a different shape of problem
(screen mirroring, not telemetry frames) and would likely need its own
research pass before porting — not started here.
