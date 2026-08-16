# OpenTrip *(working name)*

A free, open-source driving trip tracker for Android and iOS — the same idea as
apps like TripRank, but with no subscription, no paywalled features, and a
codebase anyone can audit, self-host, or extend.

## Get a build

Every push to `main` builds and tests the whole app via GitHub Actions and
publishes the APKs to the **["Latest build" release](../../releases/tag/latest)**
— on a phone, open that link and download `app-arm64-v8a-release.apk`
(works on basically any Android phone from the last ~8 years), then
sideload it. No local Flutter/Android toolchain needed just to try it.
Login (Google/email) only works in these builds if the repo has
`SUPABASE_URL`/`SUPABASE_ANON_KEY`/`GOOGLE_WEB_CLIENT_ID` set as Actions
secrets (see [docs/AUTH_SETUP.md](docs/AUTH_SETUP.md)) — without them the
build still works fine via the local guest mode, just without cloud login.

This repo is in active development. What exists today:

- **`packages/kawasaki_rideology_ble/`** — a pure-Dart library that speaks the
  Kawasaki Rideology BLE protocol directly, so the app can read live bike
  telemetry (speed, RPM, gear, lean, brake pressure, temperatures, odometer)
  without the official Rideology app installed. First target: **Z500
  (ER500F platform)**, which covers the 2024–2026 Z500/Z500 ABS/Ninja 500
  generation. See that package's README for protocol details and the
  [validation caveat](#z500-abs-2026-validation-status) below.
- **`apps/mobile/`** — the Flutter app: Google/email login, multi-vehicle
  management, GPS trip recording with a live distance/speed/duration screen,
  trip history, and the Kawasaki BLE telemetry screen with an in-app log
  viewer for on-device debugging. Builds and installs as a real Android APK
  today; see [docs/ROADMAP.md](docs/ROADMAP.md) for what's next (cloud sync,
  maps, background recording, leaderboards).
- **`docs/`** — the vehicle-connector plugin architecture, a step-by-step
  guide for capturing and validating a new bike's BLE traffic, and how to
  configure login ([`AUTH_SETUP.md`](docs/AUTH_SETUP.md) — you'll need your
  own free Supabase project and Google OAuth client; nothing shared is
  pre-configured, by design, since this is meant to be self-hostable).

## Why this exists

TripRank (triprank.co) is a solid app but closed-source and subscription
gated ($6.99–$39.99/yr for the full feature set). This project reimplements
the same category of app — GPS trip tracking, distance/territory leaderboards,
trip history — as something free and open, and adds a capability TripRank
doesn't have: reading telemetry straight from the vehicle over Bluetooth,
the way Kawasaki's Rideology app or CFMoto's MotoPlay do for their own bikes.

## Legal / safety posture

- The Kawasaki connector talks only to the **unencrypted BLE GATT interface
  the bike already advertises for pairing** — the same channel Kawasaki's own
  app uses. Nothing here defeats encryption, DRM, or a paid feature gate.
  See [`NOTICE.md`](NOTICE.md) for the upstream project this was derived from
  and its license.
- `Kawasaki` and the Kawasaki logo are trademarks of Kawasaki Motors, Ltd.
  This project is unofficial, unaffiliated, and not endorsed by Kawasaki.
- **This is not a safety device.** Never interact with a phone while riding.
  Pair, start, and stop tracking only while stopped and parked. See
  `docs/VEHICLE_CONNECTORS.md` for the full disclaimer.

## Z500 ABS 2026 validation status

**Confirmed working against a real 2026 Z500 ABS unit.** The bike
connected, completed the startup handshake, and streamed live telemetry
that decoded to physically self-consistent values while parked: gear 0
(neutral), speed 0, RPM 0, throttle 0%, and — notably — both water
temperature and inlet air temperature independently decoded to the same
16°C cold-engine reading from two different byte offsets using the same
`raw − 40` formula. That kind of agreement between independently-gated
fields is a strong signal the byte offsets and scaling are correct, not
just that the connection didn't crash. The 0x4B (riding-log-high) frames
this unit sent were all `0xFF` padding, confirming the "not exposed on
this platform" note in `packages/kawasaki_rideology_ble/README.md`.

The bundled config (`z500_er500f_config.json`) originally comes from a
capture against a Z500 (ER500F platform), reverse-engineered by the
upstream Home Assistant project this connector is ported from — the 2026
Z500 ABS confirmation above shows that config applies unchanged across
model years on this platform, as expected.

If you hit a field that looks wrong on your own unit:

1. Follow [`docs/CAPTURE_GUIDE.md`](docs/CAPTURE_GUIDE.md) to capture an HCI
   snoop log while pairing/using the official Rideology app.
2. Run the sample frames you capture through
   `packages/kawasaki_rideology_ble/test/parser_test.dart` (or a quick
   script) to confirm decoded values match the bike's own dash.
3. Open an issue/PR with anything that differs — mismatched byte offsets,
   different `info_config_flags` (which fields your specific unit supports),
   or a different advertised name.

## Repo layout

```
packages/kawasaki_rideology_ble/   Dart protocol library (no Flutter dep)
apps/mobile/                       Flutter app skeleton (iOS + Android)
docs/                              Architecture, roadmap, capture guide
NOTICE.md                          Third-party attribution (Apache-2.0)
```
