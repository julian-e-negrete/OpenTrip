# Roadmap

## Done

- **Kawasaki Rideology BLE connector** (`packages/kawasaki_rideology_ble/`):
  protocol constants, frame builder, byte-level parsers for the frames a
  trip tracker actually needs (live telemetry, odometer/trip, temps),
  startup-handshake orchestration, and golden-fixture tests ported from
  real captured frames.
- **Flutter app skeleton** (`apps/mobile/`) wiring that connector to a
  live-telemetry screen via `flutter_blue_plus`.

## Not done yet — this is a vehicle-connector slice, not a full app

The original ask was "the same thing TripRank does, but free and open" —
GPS trip recording, distance/territory leaderboards, trip history, social
features — *plus* direct vehicle telemetry. Only the vehicle-telemetry
half exists so far. In rough build order:

1. **Platform scaffolding.** `apps/mobile/` has a `pubspec.yaml` and
   `lib/`, but no `android/`/`ios/` platform folders yet — those need
   `flutter create .` run from a machine with the Flutter SDK installed
   (unavailable in the environment this was built in). Also needs Android
   manifest entries for `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT`/location
   permissions, and iOS `Info.plist` entries for Bluetooth + location
   usage descriptions.
2. **GPS trip recording core.** Background location capture (start/stop
   detection, route as a point sequence), distance/duration/speed
   calculation. `OpenTracks` (F-Droid) is a solid reference for the
   battery-efficient recording pattern.
3. **Local trip storage + history UI.** SQLite/Drift for on-device trip
   records before anything touches a server.
4. **Maps.** MapLibre GL + OpenStreetMap tiles for route replay — no
   Mapbox/Google billing dependency.
5. **Backend for leaderboards/social.** Self-hostable by design (matches
   this project's "free and open" premise) — Supabase (Postgres + PostGIS
   + Auth + Realtime, itself open-source and self-hostable) is a
   reasonable default; `FitTrackee`/`Endurain` are useful references for
   the self-hosted-activity-tracker shape.
6. **Territory/leaderboard/trophy logic**, mirroring TripRank's four
   ranked categories (distance, longest drive, territory explored,
   trophies) — deliberately *not* speed-based, both because that's the
   safer design and because it sidesteps encouraging risky riding.
7. **Wire vehicle telemetry into trip records.** Once (2) exists, a
   connected bike's speed/RPM/lean/brake data should attach to the GPS
   trip as enrichment — this is where the Kawasaki connector actually pays
   off for the tracker, beyond being a standalone live-telemetry screen.

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
