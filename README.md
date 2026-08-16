# OpenTrip *(working name)*

A free, open-source driving trip tracker for Android and iOS — the same idea as
apps like TripRank, but with no subscription, no paywalled features, and a
codebase anyone can audit, self-host, or extend.

This repo is in early scaffolding. What exists today:

- **`packages/kawasaki_rideology_ble/`** — a pure-Dart library that speaks the
  Kawasaki Rideology BLE protocol directly, so the app can read live bike
  telemetry (speed, RPM, gear, lean, brake pressure, temperatures, odometer)
  without the official Rideology app installed. First target: **Z500
  (ER500F platform)**, which covers the 2024–2026 Z500/Z500 ABS/Ninja 500
  generation. See that package's README for protocol details and the
  [validation caveat](#z500-abs-2026-validation-status) below.
- **`apps/mobile/`** — a minimal Flutter app skeleton wiring the Kawasaki
  package to a live telemetry screen. Not yet a trip tracker — see
  [docs/ROADMAP.md](docs/ROADMAP.md) for what's next (GPS recording, maps,
  leaderboards, backend).
- **`docs/`** — the vehicle-connector plugin architecture, and a step-by-step
  guide for capturing and validating a new bike's BLE traffic.

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

The bundled config (`z500_er500f_config.json`) comes from a real capture
against a Z500 (ER500F platform), reverse-engineered by the upstream Home
Assistant project this connector is ported from. The Z500 ABS 2026 model
year shares that ER500F chassis/ECU platform, so the same GATT service,
frame protocol, and field layout are very likely to apply unchanged —
Kawasaki has not been observed to change the BLE protocol between trims or
model years on this platform. **It has not been verified against a physical
2026 Z500 ABS unit by this project.** If you have access to the bike:

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
