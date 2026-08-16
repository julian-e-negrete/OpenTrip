# Vehicle connectors

## What this is

A plugin-style layer that reads live telemetry directly from a
motorcycle's own Bluetooth interface — the same channel the manufacturer's
companion app uses — instead of requiring that app to be installed. The
first (and currently only) connector targets Kawasaki's Rideology BLE
protocol.

This is the same category of thing as:

- **Gadgetbridge** — reverse-engineered the BLE protocols of 100+ wearables
  so they work without their manufacturers' apps.
- **Home Assistant's Kawasaki Rideology integration** — the project this
  connector is directly ported from (see `/NOTICE.md`).
- **open-cfmoto** — reimplements CFMoto's MotoPlay dash-mirroring protocol
  independently of CFMoto's own app.

## Why a plugin architecture

Each manufacturer's BLE protocol is its own reverse-engineering effort,
discovered by capturing real traffic from a real bike, and it can drift
between models or firmware revisions. Gadgetbridge's approach — one
self-contained module per device family, sharing a common interface —
is what let it scale past a handful of devices without every addition
risking every other one. This repo follows the same shape:

```
packages/
  kawasaki_rideology_ble/     <- one connector, one package, one protocol
  <next_brand>_ble/           <- a future connector lives here, same shape
apps/mobile/lib/vehicle/
  flutter_blue_plus_transport.dart   <- the ONE place a BLE plugin is imported
```

Each connector package:

- Has **zero dependency on a BLE plugin**. It defines/consumes an abstract
  `BleTransport` interface (connect, discover, write, notify-stream) and
  leaves the actual radio I/O to the app layer. This is what makes the
  protocol logic unit-testable with plain `dart test` against captured
  byte fixtures, no phone or bike required.
- Ships its own `BikeConfig`-shaped model configs, since two bikes on the
  same protocol can support different subsets of telemetry fields.
- Carries its own attribution file if it's derived from someone else's
  reverse-engineering work (see `kawasaki_rideology_ble/README.md`).

## Adding a new bike model (same brand, e.g. a different Kawasaki)

If the bike advertises as `Kawasaki-XXXX` and uses the same service/
characteristic UUIDs (very likely, if it also runs "Rideology the App"),
you probably don't need new code — you need a new `BikeConfig`:

1. Capture that bike's traffic per [`CAPTURE_GUIDE.md`](CAPTURE_GUIDE.md).
2. Note which fields the 0x40 (MC info config) frame reports as
   supported/unsupported for this specific unit.
3. Copy `lib/src/configs/z500_er500f.dart` as a template, adjust `model`,
   `supportedFields`, and `infoConfigFlags` to match your capture.
4. Add golden-frame test cases to `test/parser_test.dart` using your real
   captured bytes.

## Adding a new brand

1. New package under `packages/<brand>_<protocol>_ble/`, same internal
   shape as `kawasaki_rideology_ble/` (protocol IDs, frame builder,
   parsers, `BleTransport` interface, `Client` orchestrator).
2. New transport adapter under `apps/mobile/lib/vehicle/`.
3. A `NOTICE.md` entry if you're building on someone else's published
   reverse-engineering (attribute it — that's the whole reason this was
   possible for Kawasaki).

## Safety and legal posture

- **Read-only telemetry, unencrypted BLE, no DRM circumvention.** This
  connector talks to the same unauthenticated (or PIN-paired, not
  encrypted-content) GATT interface the official app uses. It does not
  defeat encryption, does not unlock a paid feature, and does not modify
  vehicle behavior — see the upstream project's own disclaimer, preserved
  in spirit here: *"The main purpose... is to access data for education
  and telemetry. It is not intended to modify vehicle behavior."*
- **If a manufacturer ever adds real encryption/authentication** to a
  bike's telemetry channel, bypassing that moves into different legal
  territory (DMCA §1201-style anti-circumvention in the US, and
  equivalents elsewhere). Don't do that; open an issue instead of shipping
  a workaround.
- **Trademarks.** Manufacturer names/logos referenced here (Kawasaki,
  Rideology, etc.) are used only to describe compatibility, not to imply
  endorsement. This project is unofficial and unaffiliated.
- **Never interact with a phone while riding.** Pairing, connecting, and
  reviewing telemetry should happen only while stopped and parked — same
  rule as any other phone-and-vehicle app. See
  `packages/kawasaki_rideology_ble/README.md` and the upstream project's
  own safety notice.
