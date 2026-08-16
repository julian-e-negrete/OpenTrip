# Roadmap

## Done

- **Kawasaki Rideology BLE connector** (`packages/kawasaki_rideology_ble/`):
  protocol constants, frame builder, byte-level parsers for the frames a
  trip tracker actually needs (live telemetry, odometer/trip, temps),
  startup-handshake orchestration, and golden-fixture tests ported from
  real captured frames.
- **Flutter app + platform scaffolding** (`apps/mobile/`): real `android/`
  (built and installable) and `ios/` (scaffolded, unbuildable without a
  Mac) projects, wired to the BLE connector via `flutter_blue_plus`, plus
  an in-app BLE log viewer (`screens/log_screen.dart`) with one-tap
  copy-to-clipboard for pulling logs off a phone with no computer.
- **Auth** (`auth/`): Google sign-in (native ID-token flow) and
  passwordless email (6-digit OTP, no deep-linking needed) via Supabase
  Auth. Fails loud with setup instructions
  (`auth/supabase_not_configured_screen.dart`) rather than crashing when
  no Supabase project is wired in yet — see `docs/AUTH_SETUP.md` for the
  (unavoidable, you-bring-your-own-project) setup steps.
- **Multi-vehicle trip recording** (`data/`, `trip/`, `vehicles/`,
  `trips/`): on-device SQLite (vehicles / trips / trip_points tables,
  scoped per signed-in user), a vehicle CRUD screen, a GPS recorder
  (`trip/location_recorder.dart` — haversine distance, GPS-glitch
  rejection, accuracy filtering) with a live start/stop recording screen,
  and trip history + detail views.

## Not done yet

1. **Cloud sync.** Trips/vehicles are local-only right now — login
   establishes *who you are* (and is required to record a trip, since
   every local row is scoped to a user id) but nothing is pushed to
   Supabase's Postgres yet. That's the natural next slice once auth is
   confirmed working end-to-end: mirror `data/local_database.dart`'s
   schema into Supabase tables with row-level security scoped to
   `auth.uid()`, then sync opportunistically when online.
2. **Background recording.** GPS tracking currently only runs while the
   app is in the foreground — `geolocator`'s stream stops if Android kills
   the app in the background. A foreground service (e.g.
   `flutter_foreground_task`, MIT-licensed) is the fix; not added yet to
   keep this slice's scope verifiable in one pass.
3. **Maps.** Route points are already being recorded and persisted
   per-trip — `trips/trip_detail_screen.dart` shows stats only, no map.
   MapLibre GL + OpenStreetMap tiles is still the plan (no Mapbox/Google
   billing dependency).
4. **Territory/leaderboard/trophy logic**, mirroring TripRank's four
   ranked categories (distance, longest drive, territory explored,
   trophies) — deliberately *not* speed-based. Needs cloud sync (1) first,
   since leaderboards are inherently cross-user.
5. **Wire vehicle telemetry into trip records.** A vehicle can be flagged
   `kawasakiRideology` today (`data/models/vehicle.dart`), but the
   recording screen doesn't yet connect to it and attach live telemetry
   (speed/RPM/lean/brake) to the trip — that's where the BLE connector
   actually pays off for the tracker, beyond being a standalone demo
   screen. Straightforward once (2) exists, since both need the app alive
   in the background during a ride.

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
