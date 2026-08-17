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
- **Territory map** (`gamification/territory_map_screen.dart`,
  `get_territory_map()` in `supabase/leaderboard.sql`): a world map of
  conquered zones — every rider's claimed grid cells drawn as filled
  rectangles over OpenStreetMap tiles, yours highlighted, everyone
  else's colored by a stable per-rider hash so the same person always
  reads as the same color across loads. Needed its own `security
  definer` function for the same reason the leaderboard did (RLS blocks
  cross-user reads even through a view) — but deliberately returns only
  `(cell_key, user_id, display_name)`, never a raw trip route or
  timestamp, so it can't be used to reconstruct anyone's actual path.
  Reachable via a map icon on the Leaderboard screen; guests get the
  same "sign in" gate as the leaderboard itself.
- **One shared BLE connection, not two** (`vehicle/ble_connection_service.dart`):
  the standalone Vehicle tab (`screens/vehicle_screen.dart`) and the
  Record tab's "Connect bike" card (`trip/recording_screen.dart`) used to
  each run their own `KawasakiConnector.connect()` and own a separate
  `KawasakiClient` — connecting on one tab and switching to the other
  triggered a second, independent scan + GATT connect to the same bike,
  which most BLE peripherals (this one included) reject or silently
  drop the first connection over. Fixed with a singleton
  (`BleConnectionService.instance`) that owns the one real connection;
  both screens read and drive it through there instead. Connecting or
  disconnecting on either tab now shows up on both immediately. As a
  consequence, ending a trip recording no longer auto-disconnects the
  bike (it used to) — disconnecting is now a user action on either tab,
  not tied to a trip's lifecycle, since the connection can outlive any
  one screen that's using it.
- **Trip deletion** (`trips/trip_history_screen.dart`,
  `trips/trip_detail_screen.dart`): swipe a trip left in the list, or use
  the delete icon on its detail screen — both confirm first. Removes the
  trip and its GPS points locally and (best-effort) remotely; territory
  cells and trophies earned from that trip are deliberately left alone,
  since you still covered that ground either way.
- **Country field** (`data/catalog/country_catalog.dart`,
  `account/country_picker.dart`): a rider's country, captured on the
  Account tab as a picked ISO 3166-1 code (searchable full-screen
  picker, same "structured, not free text" reasoning as the vehicle
  catalog) rather than free text — the point is that it stays usable
  later (e.g. slicing a future leaderboard by country), which free text
  never reliably is. Syncs to Supabase (`profiles.country_code`) but
  isn't exposed to any other user yet — same private-until-a-
  security-definer-function-says-otherwise posture as everything else
  in `profiles`; nothing currently reads it back out.
- **Private-profile opt-out** (`profiles.leaderboard_visible` in
  `supabase/schema.sql`, a new toggle on the Account tab): signing in
  and syncing no longer has to mean being ranked. Off excludes a rider
  from `get_leaderboard()`, `get_territory_map()`
  (`supabase/leaderboard.sql`), and `get_friends_leaderboard()`
  (`supabase/friends.sql`) all at once — one flag, every ranking view,
  rather than a per-view setting that would be easy to get into a
  confusing half-opted-out state.
- **A friends layer** (`friends/`, `supabase/friends.sql`,
  `leaderboard/leaderboard_screen.dart`'s new Global/Friends toggle):
  search for a rider by display name, send/accept/decline requests, and
  a `get_friends_leaderboard()` scoped to you and your accepted friends
  — same four categories as the global leaderboard, just a smaller,
  more personal list. Every write to the new `friendships` table goes
  through a `security definer` function rather than a direct
  insert/update/delete (see the comment at the top of `friends.sql`) —
  RLS's per-row checks can't express "does a reverse request already
  exist, and should this accept it instead of creating a contradictory
  second row," but a function can, atomically. Reachable via the people
  icon on the Leaderboard screen. Sign-in only, like the rest of the
  social features — no cross-device "friends" concept for a local guest.
- **Auto-start drive detection** (`autostart/`): a trip starts and stops
  itself once driving is detected — no tapping "Start recording," and it
  works even if OpenTrip was fully closed, matching what TripRank/Google
  Maps do. Given the choice between that and a lighter "only while the
  app is open" version, this was built as the full always-on kind
  deliberately, at real architectural cost — see below.

  Two cooperating pieces: `flutter_activity_recognition` wraps Android's
  `ActivityRecognitionClient` to report `IN_VEHICLE`/`STILL`/etc.
  transitions; `flutter_foreground_task` runs that subscription inside
  its own persistent background isolate (a second foreground-service
  notification, independent of `trip/location_recorder.dart`'s own —
  the two never run at once, and this one has `stopWithTask: false` and
  `autoRunOnBoot: true`, which is what actually gets it past a swipe-away
  or a reboot). `IN_VEHICLE` sustained 45s starts a trip (against the
  most-recently-used vehicle — there's no UI to ask which one);
  `STILL`/`WALKING`/`RUNNING` sustained 3 minutes ends it. Both numbers
  are a first guess, not a measurement — there's no way to tune a
  debounce window like this without a real device actually driving
  around, the same caveat every background-service change in this
  project has needed.

  A trip this task starts is GPS-only — connecting a bike over BLE still
  needs the scan/connect flow on the Vehicle tab, which a background
  isolate has no reasonable way to drive unattended. The two isolates
  (this background one, and the main UI one `trip/recording_screen.dart`
  runs in) don't share Dart memory even though they're the same OS
  process, so "is a trip currently active" is answered from the database
  (`TripRepository.activeTripFor`, keyed on `ended_at IS NULL`) rather
  than in-memory state — both the detector and the manual Start button
  check it first, so they can't ever race into two competing recordings.
  Opening the app while an auto-started trip is running shows it as
  "Recording automatically" on the Record tab; stopping it from there
  sends a message to the background isolate rather than calling a local
  recorder, since that isolate is the one actually holding it.

  **Known limitations, accepted rather than built around:** the
  start/stop debounce windows above will very likely need retuning once
  this actually runs on a bike or in a car. Activity Recognition can't
  distinguish your own vehicle from being a passenger in a bus or train
  — there's no way around that with this API. If the background service
  itself gets killed and restarted mid-trip (rare, but possible under
  memory pressure), the resumed trip's distance undercounts whatever
  happened during the gap — recomputing it exactly would mean
  reconstructing pre-restart state with more precision than seemed worth
  the complexity for an edge case this narrow.
- **Speed-camera & red-light-camera alerts** (`trip/camera_alerts.dart`):
  a haptic buzz (works whether or not anyone's looking at the screen —
  the point, while driving) plus a SnackBar
  (`trip/recording_screen.dart`) or a brief notification-text flash
  (`autostart/driving_detector_task.dart`, since a background isolate
  has no screen to show a SnackBar on) when passing within 500m of a
  camera. Deliberately doesn't alert on plain traffic signals —
  OpenStreetMap's `highway=traffic_signals` tag exists at nearly every
  intersection in a city, and alerting on all of them would be noise,
  not safety information, and isn't what real navigation apps do
  either. Only actual enforcement points: fixed speed cameras
  (`highway=speed_camera` / `enforcement=maxspeed`) and red-light
  cameras (`enforcement=traffic_signals`). Built as a capability of
  `LocationRecorder` itself, so both the manual recording flow and the
  auto-start detector get it automatically rather than each wiring
  their own. Data comes from the public Overpass API — same
  OpenStreetMap source as the map tiles
  (`trips/trip_detail_screen.dart`), same fair-use caveat that comment
  already documents, kept well inside it by querying once per trip and
  again only every 15km of travel, never per GPS fix. No new
  permission (`INTERNET` was already declared), on by default —
  network failures just mean no alerts for that stretch, never a
  failed recording. Coverage is only as good as OpenStreetMap's for a
  given area, which varies a lot by region.
- **Driving-behavior stats** (`trip/driving_math.dart`): hardest
  acceleration, hardest braking, hardest cornering — each as a max
  g-force plus a count of "hard" events — for every trip, on every
  vehicle, not just BLE-equipped bikes (which already got a version of
  this — lean angle, brake pressure — straight from the bike itself).
  Deliberately computed from the GPS stream already flowing through
  `LocationRecorder` (speed for accel/braking, course-over-ground turn
  rate for cornering — a·v = v·dθ/dt) rather than the phone's
  accelerometer. A raw accelerometer reading is in the *phone's own*
  reference frame — mounted upright, flat in a cupholder, in a pocket,
  its axes point in completely different real-world directions each
  time, and telling "that jolt was braking" from "that jolt was a hard
  right turn" needs knowing the phone's orientation relative to the
  vehicle, a calibration problem this project didn't take on. Reporting
  confident-looking directional numbers built on data that can't
  actually distinguish them would have been worse than not having the
  stat. GPS course-over-ground is already in a real-world (compass)
  reference frame regardless of phone orientation, at the cost of being
  noisier than a real IMU — traded deliberately for numbers that are
  honestly what they claim to be. Shown on trip detail under "Driving
  behavior" whenever a trip has enough accepted GPS fixes to compute
  it. Thresholds for what counts as "hard" (`_hardAccelThresholdMps2`
  etc. in `location_recorder.dart`) are a first guess from published
  telematics ranges, not a measurement — same "needs real-device
  tuning, no way around that" caveat as the auto-start debounce windows
  and camera-alert radius above. Not tied to any leaderboard or
  trophy — TripRank's own positioning is explicit that speed/behavior
  is "for reference," never ranked, and this mirrors that.

## Not done yet

Ordered by priority, from a feature comparison against TripRank (see
`/README.md` for what TripRank is) — highest-value gaps first. An item
being here means "identified and worth doing," not "in progress."

1. **Photo sync.** Vehicle/profile photos are local-only — see "Cloud
   sync" above. Needs a Supabase Storage bucket + policies.
2. **Animated trip replay on satellite map.** Trip detail currently
   shows a static route line over OpenStreetMap street tiles
   (`trips/trip_detail_screen.dart`); TripRank animates the route over
   satellite imagery. Satellite tiles alone are a tile-provider swap
   (see that file's doc comment); the playback animation is new work.
3. **Monthly recap.** A generated summary of a rider's month — would
   reuse `gamification_repository.dart`'s existing aggregation
   patterns, just windowed by date instead of all-time.
4. **Shareable trip stat-card image.** Render a trip's key numbers as a
   shareable image (e.g. via Flutter's `RepaintBoundary` capture) —
   useful for organic growth, no backend changes needed.
5. **iOS, actually shippable.** The `ios/` project is scaffolded and
   wired for feature parity (Info.plist entries, `AppleSettings` in
   `trip/location_recorder.dart`) but has never been built or run —
   this project has no Mac. Everything iOS-related in this roadmap is
   unverified until that changes.
6. **Car clubs / groups.** Lowest priority of the identified gaps —
   TripRank's own description of what a "car club" actually does
   (chat? shared challenges? just a named group on the leaderboard?)
   couldn't be confirmed even from its own marketing pages, so there's
   not yet a clear feature to build toward.
7. **AI car-modification visualizer.** Also low priority — a novelty
   feature with an external paid image-generation API dependency
   (TripRank uses fal.ai), not core to trip tracking or vehicle
   connectivity, which is where this project's actual differentiation
   is.

**Possible implementation — things neither app has, surfaced by the
same comparison, and worth treating as real candidates rather than a
footnote:**

- **GPX / raw trip data export.** Every point is already in
  `trip_points` (`data/local_database.dart`); this is a serializer plus
  a share-sheet call, not new data collection. Genuinely useful (feeds
  Strava, Komoot, a GIS tool, whatever) and low-risk to build.
- **Maintenance/OBD tracking.** A vehicle-scoped log (service dates,
  odometer-based reminders) would fit naturally next to `vehicles/` —
  doesn't need OBD-II hardware to start, just manual entries; BLE-
  equipped vehicles could eventually prefill odometer from
  `packages/kawasaki_rideology_ble`'s already-parsed trip-meter frames.
- **A web dashboard.** Bigger lift — a whole second frontend against
  the same Supabase schema (view-only trip history/stats would be a
  reasonable first cut, not full recording). No existing code to build
  from, unlike the other two.

Any of these would be genuine differentiation rather than parity-chasing
if picked up.

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
