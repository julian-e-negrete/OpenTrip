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
- **Territory map, as its own tab** (`gamification/territory_map_screen.dart`,
  `get_territory_map()`/`get_friends_territory_map()` in
  `supabase/leaderboard.sql`/`friends.sql`): a world map of conquered
  zones — every rider's claimed grid cells drawn as a soft heat glow (see
  the redesign below) over a CARTO basemap, yours highlighted, everyone
  else's colored by a stable per-rider hash so the same person always
  reads as the same color across loads. A Global/Friends `SegmentedButton` (same
  pattern as the Leaderboard tab's) switches between every non-opted-out
  rider and just you plus your accepted friends. Needed its own
  `security definer` functions for the same reason the leaderboard did
  (RLS blocks cross-user reads even through a view) — but deliberately
  return only `(cell_key, user_id, display_name)`, never a raw trip
  route or timestamp, so they can't be used to reconstruct anyone's
  actual path. Promoted from an icon buried on the Leaderboard screen to
  a full bottom-nav tab (`home_shell.dart`) on request; guests get the
  same "sign in" gate as the leaderboard itself.
- **Territory map redesign, take one: heat glow instead of flat
  rectangles** (superseded by the extruded-column redesign below —
  `_TerritoryHeatLayer`/`_HeatPainter` no longer exist, kept here as the
  historical record of what changed and why)
  (`territory_cells.visit_count` in
  `supabase/leaderboard.sql`): the original version drew every claimed
  cell as a flat-colored rectangle with a visible border — functionally
  fine, visually a checkerboard, and didn't read as "territory" so much
  as "a spreadsheet over a map." Replaced with a purpose-built heatmap
  layer (flutter_map has no built-in one): each cell becomes a soft
  radial-gradient blob sized to overlap its neighbors, so a contiguous
  ridden area reads as one continuous glow. Cells from the same rider are
  composited on their own `saveLayer` with `BlendMode.plus` so
  overlapping visits *brighten* together instead of just re-drawing the
  same flat color — which is also what makes intensity meaningful: a
  cell's glow strength now comes from `territory_cells.visit_count`
  (incremented on every revisit — `GamificationRepository.addTerritoryCells`
  switched from insert-and-ignore-duplicates to a
  `... ON CONFLICT DO UPDATE SET visit_count = visit_count + 1` upsert),
  capped at 6 visits for full intensity so a daily-commute cell lights up
  solid without needing dozens of passes. `get_territory_map()`/
  `get_friends_territory_map()` both return `visit_count` now, and the
  local→remote push overwrites (not increments) the remote value, since
  the local row is already the authoritative cumulative count. Paired
  with switching the basemap from OpenStreetMap's default colorful street
  tiles — which fought the glow for attention and didn't sit well with
  either theme — to CARTO's Dark Matter/Positron tile sets, picked by the
  app's current brightness so the map always matches
  `theme/app_theme.dart` instead of looking bolted on.
- **Territory map redesign, take two: extruded columns instead of a
  glow** (superseded by take three below — actually rendered and looked
  at this one before shipping the next redesign, and it was bad enough
  in practice to revert outright rather than tune; kept as the
  historical record) (`gamification/territory_map_screen.dart`'s
  `_TerritoryColumnLayer`/`_ColumnPainter`): the glow version above read
  better than flat rectangles but was compared side by side against two
  other options — three mocked-up "cube" concepts, each grounded in a
  real precedent (deck.gl's HexagonLayer, fixed-viewpoint isometric
  voxels like R's `isocubes`/Cesium Heatbox, and a flat CSS bevel) — and
  the deck.gl-style extruded-column look won. Since flutter_map has no
  tiltable 3D camera the way deck.gl/Mapbox do, this fakes it in 2D: each
  cell's real geographic footprint is drawn as normal, a second copy of
  that same rectangle is drawn shifted up-and-right by the column's
  height, and the gap between the two is filled in as the column's front
  and right walls (flat-shaded lighter-top/right-darker, not dynamically
  lit) — the classic "shift the roof, fill the walls" cheat behind most
  flat isometric icon art, not real 3D geometry. `visit_count` now drives
  column *height* (capped at 6 visits for the tallest column) instead of
  glow intensity, and color is constant per rider rather than
  intensity-modulated. Columns are painted back-to-front by their base's
  screen position in one global pass — not grouped per rider like the
  glow version's `BlendMode.plus` layers — since opaque solid faces need
  correct occlusion between *every* column regardless of owner, not just
  overlaps within one rider's own cells.
- **Territory map redesign, take three: flat hexagons, copying TripRank
  directly** (`gamification/territory.dart` rewritten around hexagonal
  axial coordinates, `territory_map_screen.dart` back to a plain
  `PolygonLayer`): take two's columns were rendered and actually looked
  at (a Flutter `CustomPainter` recorded straight to a PNG via
  `PictureRecorder`/`toImage`, no device needed) before deciding whether
  to ship again — and they looked bad. Since territory cells are dense
  and contiguous (you ride through *adjacent* streets, not scattered
  points), leaning columns on cells that touch every neighbor collided
  into each other on all sides; insetting a gap and shrinking the lean
  made it less bad but never actually clean. deck.gl's HexagonLayer
  (take two's inspiration) is normally used for sparse point-density
  data with real gaps between cells — territory doesn't have that
  property, so the whole approach was the wrong tool, not a tuning
  problem. Replaced with a direct copy of how TripRank itself renders
  this (screenshots provided directly): flat-topped hexagons, not
  squares, semi-transparent fill + a visible border, no height, no glow.
  Hexagons tile a winding road more naturally than a rectangular grid —
  the chain follows the actual street shape instead of a stair-stepped
  checkerboard. Cell addressing moved from `"latCell:lngCell"` to axial
  hex coordinates `"q:r"` (see territory.dart's cube-rounding comment for
  why naive per-axis rounding doesn't work near a hex boundary) — same
  two-integers-separated-by-a-colon shape as before, completely
  different meaning, so old `territory_cells` rows couldn't just keep
  working: they'd silently reinterpret as hex coordinates and draw in
  the wrong place. Cleared instead of migrated (`LocalDatabase` version
  12's `onUpgrade`, and a one-time `delete from territory_cells` run
  directly against Supabase — not folded into `leaderboard.sql`, since
  that file is meant to be safely re-run and a delete doesn't belong in
  a "safe to re-run" script). Claims refill as each area is ridden
  through again. `territory_cells.visit_count` (take one's addition)
  is untouched and still collected — just not visually used by this
  screen anymore, since matching the reference meant a flat, uniform
  color per rider rather than intensity-modulated.
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
- **Speed-camera & red-light-camera alerts** (`trip/camera_alerts.dart`):
  a haptic buzz (works whether or not anyone's looking at the screen —
  the point, while driving) plus a SnackBar
  (`trip/recording_screen.dart`) when passing within 500m of a camera.
  Deliberately doesn't alert on plain traffic signals —
  OpenStreetMap's `highway=traffic_signals` tag exists at nearly every
  intersection in a city, and alerting on all of them would be noise,
  not safety information, and isn't what real navigation apps do
  either. Only actual enforcement points: fixed speed cameras
  (`highway=speed_camera` / `enforcement=maxspeed`) and red-light
  cameras (`enforcement=traffic_signals`). Built as a capability of
  `LocationRecorder` itself rather than `trip/recording_screen.dart`
  wiring its own. Data comes from the public Overpass API — same
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
  tuning, no way around that" caveat as the camera-alert radius above.
  Not tied to any leaderboard or
  trophy — TripRank's own positioning is explicit that speed/behavior
  is "for reference," never ranked, and this mirrors that.
- **Animated trip replay + satellite tiles** (`trips/trip_detail_screen.dart`):
  a play/pause control animates a marker along the route, and a
  satellite/street toggle switches `TileLayer` between
  `tile.openstreetmap.org` and Esri's public World Imagery service
  (`server.arcgisonline.com` — no API key, same "fine at this app's
  scale, not for heavy production traffic" posture as the street tiles
  already had). Replay is fixed at 18 seconds regardless of actual trip
  length (nobody would watch an hour-long drive played back in real
  time), but the *marker* within that window is still paced by the
  trip's real elapsed time (`trip/route_replay.dart`,
  `positionAtProgress`/`pointCountAtProgress` — tested), not by point
  index: a stretch where you idled at a light plays slower than the
  open road, exactly as it happened, rather than both taking the same
  slice of the 18 seconds just because they have similar point counts.
- **Monthly recap** (`gamification/monthly_recap_screen.dart`): the
  same all-time aggregations the Account tab and leaderboard already
  show, windowed to one month via new range-scoped queries
  (`TripRepository.listForUserInRange`,
  `GamificationRepository.territoryCellCountInRange`/
  `trophyKeysEarnedInRange`) instead of new data collection. Distance,
  trip count, time driving, longest trip, new territory explored, and
  any trophies earned that month, with prev/next month navigation.
  Reachable from the Account tab; works for guests too, since it's all
  local and keyed by whichever id `CurrentUser` resolves to — unlike
  the leaderboard/friends screens, nothing here needs another user's
  data.
- **Shareable trip stat-card image** (`trips/stat_card_screen.dart`): a
  branded card (distance, time, avg/max speed, vehicle, date) rendered
  via `RepaintBoundary.toImage()` and handed to the OS share sheet via
  `share_plus` — reachable via a share icon on trip detail. Purely
  client-side, no backend involved in generating or hosting the image.
- **Phone-based lean angle tracking** (`trip/lean_angle_tracker.dart`):
  an opt-in "Track lean angle" toggle on the Record tab (motorcycles
  only) uses the phone's own accelerometer to track max lean for any
  bike, not just BLE-connected Kawasakis (which already get a real
  lean reading from the bike's own IMU — `bleMaxLeanDeg`, independent
  of this and shown separately on trip detail if both exist). A
  fundamentally different problem from the driving-behavior stats
  above: lean angle only needs the phone rigidly mounted to the bike,
  not knowledge of which way it's traveling, so — unlike accel/braking/
  cornering — an accelerometer-only approach is actually the right
  tool here, not a compromise. Method:
  `angleBetweenVectorsDeg` (tested) measures the angle between the
  live (smoothed) gravity vector and a reference vector calibrated
  from the first ~800ms of readings when a tracked trip starts
  (assumes the bike is upright and roughly stationary at that moment)
  — orientation-agnostic by construction, so it doesn't matter exactly
  how the phone is mounted, only that it's mounted at all. Deliberately
  doesn't isolate roll from pitch or fuse in the gyroscope (a wheelie
  or hard-braking dive reads as "lean" too) — a single accelerometer
  reading can't cleanly separate those, and a fake-precise filter
  pretending otherwise would be worse than an honestly-approximate
  one. Opt-in rather than always-on (unlike camera alerts/driving
  behavior) because a phone that *isn't* mounted — in a pocket, say —
  would still produce numbers that look like a real reading, which is
  worse than not having the feature. No new permission (motion
  sensors don't need one on Android, unlike the activity-recognition
  signal the now-removed auto-start feature used).
- **Per-point BLE telemetry, a live replay HUD, and vehicle mileage/service
  tracking.** Three related additions, all built on top of the trip-level
  BLE max/min stats above:
  - **Point-level telemetry** (`data/models/trip_point.dart`): each GPS
    fix now optionally carries the bike's speed/RPM/gear/throttle/lean/
    water-temp reading from whatever the latest telemetry frame happened
    to be at that moment — sampled once per accepted GPS point
    (`trip/recording_screen.dart`'s `_pointSub` listener merges in
    `_ble.telemetryNotifier.value`), not once per BLE frame (which
    arrives much faster), so point storage doesn't multiply by the
    telemetry frame rate. `trip/location_recorder.dart` itself stays
    GPS-only and knows nothing about BLE — recording_screen.dart is the
    one place a trip's GPS stream and the shared BLE connection actually
    meet.
  - **Live replay HUD** (`trips/trip_detail_screen.dart`'s
    `_TelemetryHud`): while the route replay marker is moving (or paused
    partway through), a compact instrument readout shows live speed and,
    if this trip has any point-level BLE telemetry, RPM/gear/lean too —
    read off whichever point `route_replay.dart`'s
    `pointCountAtProgress` says the marker has most recently reached, so
    the numbers track the marker rather than the trip's ever
    (behavior-stats) max/min. The replay also gained a speed control
    (1×/2×/4×/8×, cycled by tapping a chip) — `AnimationController`'s
    `duration` is only consulted when `forward()` restarts the
    simulation, so speeding up mid-replay means changing `duration` and
    calling `forward()` again to pick up the new pace for whatever
    fraction is left, not just mutating the field.
  - **Vehicle mileage & service tracking**
    (`vehicles/vehicle_detail_screen.dart`'s mileage card,
    `data/models/vehicle.dart`'s `startingOdometerKm`/
    `serviceIntervalKm`/`lastServiceOdometerKm`): current mileage prefers
    the bike's own odometer (Kawasaki Rideology's `odometerTenthKm`,
    captured last-write-wins per trip as `Trip.bleOdometerKm` — an
    odometer only ever counts up, so the most recent trip that reported
    one is authoritative) over summing recorded-trip distances, since
    the hardware count is exact and doesn't care how much of the
    vehicle's life was ridden before this app existed. Falls back to
    `startingOdometerKm + sum(trip distances)` for anything without BLE.
    Service tracking is opt-in per vehicle (a null `serviceIntervalKm`
    disables it entirely) since there's no sane app-wide default
    interval across motorcycle/car/bicycle/other. "Log service now" sets
    `lastServiceOdometerKm` to the current mileage; the card shows a
    progress bar and a "N km until service" / "overdue by N km" readout
    either way.
- **Music logging via Spotify's own local broadcast, not its Web API**
  (`android/app/src/main/kotlin/co/opentrip/opentrip_mobile/SpotifyNowPlayingStreamHandler.kt`,
  `trip/spotify_now_playing.dart`, `data/models/trip_music_event.dart`):
  investigated syncing with Spotify to log what was playing during a
  trip and — separately — creating "Jams" to share with friends on a
  group ride. Jam has zero third-party API/SDK/deep-link surface
  (confirmed against current docs) — nothing to build there. Spotify's
  Web API `currently-playing` endpoint works, but Development Mode caps
  a registered app at 5 authorized Spotify accounts total and requires
  the app owner to keep Premium active; scaling past that needs
  "Extended Quota Mode," which requires being a registered business with
  roughly 250K MAU — unreachable for a small open-source app, so that
  route was rejected as a real feature (would work for a 5-person beta,
  not for every OpenTrip user).

  Instead, this uses a completely different, undocumented-by-Spotify-as-
  an-API-but-actually-supported mechanism: Spotify's Android app sends
  `com.spotify.music.metadatachanged` as a plain Android broadcast intent
  whenever a track starts (extras: `track`/`artist`/`album`/`id`/`length`/
  `timeSent` — see
  [Spotify's own Android media-notifications tutorial](https://developer.spotify.com/documentation/android/tutorials/android-media-notifications)),
  once the user flips "Device Broadcast Status" on in Spotify's own
  Settings -> Playback. No OAuth, no developer-app registration, no user
  cap — works for every install. `SpotifyNowPlayingStreamHandler.kt`
  registers a `BroadcastReceiver` dynamically (not manifest-declared,
  since Android 8+ blocks most manifest-declared implicit receivers —
  Spotify's own tutorial registers this way too) via
  `ContextCompat.registerReceiver(..., RECEIVER_EXPORTED)`, required on
  API 33+ for receiving broadcasts sent by another app, and streams
  events to Dart over an `EventChannel`.

  Track changes are a sparse, event-driven timeline (tens per trip, not
  hundreds), so `trip_music_events` is its own table rather than riding
  along on `trip_points` the way per-point BLE telemetry does — same
  "pushed in bulk once the trip finishes, pulled lazily per-trip" shape
  as `trip_points`, just lower volume. Opt-in per recording ("Log music
  (Spotify)" toggle on trip/recording_screen.dart, independent of
  vehicle type — this is about the rider, not the bike) since it only
  does anything if Spotify is installed and that one setting is on.
  Shows a live "now playing" readout during recording, and a
  "Soundtrack" list on trip detail with how far into the trip each track
  started.

## Removed

- **Auto-start drive detection.** Built, shipped, then rolled back on
  request. It worked as designed (activity-recognition transitions
  driving a background `flutter_foreground_task` isolate that started/
  stopped trips on its own), but its actual reliability was always
  going to depend on how aggressively a given phone's OEM kills
  background services under memory pressure — worse than stock
  Android's own Doze/App Standby on some devices, and worse still on
  Android Go edition phones (common on low-RAM budget hardware), which
  are specifically tuned to reclaim background processes harder than
  standard Android. That tradeoff stopped being worth the real
  architectural cost it added (a second persistent background service,
  a second plugin dependency, cross-isolate state coordination
  throughout trip recording) for a feature whose reliability isn't
  fully in this project's control. `TripRepository.activeTripFor` and
  the cross-isolate log-bridging in `trip/location_recorder.dart` that
  existed only to support it were removed along with it;
  `trips.auto_started` stays in the local SQLite schema as a harmless,
  always-0 column rather than a destructive migration for anyone
  upgrading from a build that had it.

## Not done yet

Ordered by priority, from a feature comparison against TripRank (see
`/README.md` for what TripRank is) — highest-value gaps first. An item
being here means "identified and worth doing," not "in progress."

1. **Photo sync.** Vehicle/profile photos are local-only — see "Cloud
   sync" above. Needs a Supabase Storage bucket + policies.
2. **iOS, actually shippable.** The `ios/` project is scaffolded and
   wired for feature parity (Info.plist entries, `AppleSettings` in
   `trip/location_recorder.dart`) but has never been built or run —
   this project has no Mac. Everything iOS-related in this roadmap is
   unverified until that changes.
3. **Car clubs / groups.** Lowest priority of the identified gaps —
   TripRank's own description of what a "car club" actually does
   (chat? shared challenges? just a named group on the leaderboard?)
   couldn't be confirmed even from its own marketing pages, so there's
   not yet a clear feature to build toward.
4. **AI car-modification visualizer.** Also low priority — a novelty
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
