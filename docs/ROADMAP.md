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

## Not done yet

1. **Background recording.** GPS tracking currently only runs while the
   app is in the foreground — `geolocator`'s stream stops if Android kills
   the app in the background. A foreground service (e.g.
   `flutter_foreground_task`, MIT-licensed) is the fix; not added yet to
   keep this slice's scope verifiable in one pass.
2. **Maps.** Route points are already being recorded and persisted
   per-trip — `trips/trip_detail_screen.dart` shows stats only, no map.
   MapLibre GL + OpenStreetMap tiles is still the plan (no Mapbox/Google
   billing dependency).
3. **Territory/leaderboard/trophy logic**, mirroring TripRank's four
   ranked categories (distance, longest drive, territory explored,
   trophies) — deliberately *not* speed-based. Cloud sync now exists to
   build this on top of.
4. **Background BLE + trip pairing.** The BLE telemetry hookup (see
   "Done" above) only survives while the app is foregrounded, same
   limitation as (1) — connecting the bike, then locking the phone
   mid-ride, currently drops both the GPS stream and the BLE connection.
   Fixed by the same foreground-service work as (1).
5. **Photo sync.** Vehicle/profile photos are local-only — see "Cloud
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
