# kawasaki_rideology_ble

An independent, open-source Dart client for the BLE protocol Kawasaki's
**Rideology the App** uses to talk to compatible motorcycles. Lets you read
live telemetry — speed, RPM, gear, throttle, lean angle, brake pressure,
temperatures, fuel, odometer — directly from the bike, without installing
Kawasaki's app.

Unofficial and unaffiliated with Kawasaki Motors, Ltd. See the repo root
[`NOTICE.md`](../../NOTICE.md) for where this protocol knowledge comes from
(a real reverse-engineering effort, ported here with attribution) and
[`docs/VEHICLE_CONNECTORS.md`](../../docs/VEHICLE_CONNECTORS.md) for the
safety/legal posture.

## What's implemented

| Frame | ID | Purpose | Status |
|---|---|---|---|
| Model info | `0x03` | VIN / model string | ✅ |
| ACK | `0x20` | Generic command acknowledgement | ✅ |
| Status report | `0x30` | Block result / text chunk replies | ✅ |
| MC info config | `0x40` | Which telemetry fields this bike supports | ✅ |
| MC info | `0x41` | Odometer, trip A/B, battery voltage, fuel gauge | ✅ |
| Riding log (mid) | `0x4A` | **Live telemetry**: RPM, wheel speed, gear, throttle, lean, accel, TCS, torque, ABS status, front brake pressure | ✅ |
| Riding log (ext) | `0x45` | Water/oil/inlet-air temperature, tire pressure, odometer | ✅ |
| Meter indication init | `0x08` | Startup handshake frame | ✅ (send/parse for startup only) |
| Phone model | `0x0B` | Client identification sent to the bike | ✅ |
| EMC info | `0x42` | EV/HEV service-config-like frame | ✅ (parse only) |
| General settings / capability | `0x1B` / `0x1A` | Clock, shift-lamp settings | ⛔ not ported — not needed for trip tracking |
| Common service / service indicator | `0x1D` / `0x1E` | Maintenance due dates | ⛔ not ported yet — contributions welcome |
| Vehicle tuning / settings | `0x47` / `0x48` | Ride mode, suspension (KECS), power mode | ⛔ not ported yet — contributions welcome |
| Riding log (high) | `0x4B` | Suspension stroke, IMU axes | ⛔ not ported yet — not exposed on Z500 anyway |

The unported frames are all upstream-documented in the Python source this
was ported from (see NOTICE.md) if you want to add them — the byte layouts
are already known, it's just translation work.

## Architecture

```
BleTransport (abstract)              <- you implement this with flutter_blue_plus,
     ^                                  or anything else, in the app layer
     |
KawasakiClient                        <- connects, runs the startup handshake,
     |                                    dispatches notify frames to parsers
     v
RidingTelemetry stream                <- typed, unit-converted snapshot
```

The package has **no BLE plugin dependency**. You give it a `BleTransport`
implementation (connect, discover the Rideology service, write to the
control characteristic, subscribe to the 3 notify characteristics) and it
handles the rest: the startup frame sequence, response matching/retries,
and turning raw notify bytes into a `RidingTelemetry` snapshot.

## Quick start (once wired into an app)

```dart
final client = KawasakiClient(
  transport: FlutterBluePlusTransport(device), // your BleTransport impl
  config: BikeConfig.z500Er500f,
);

await client.connect();          // GATT connect + service discovery
await client.runStartupSequence(); // handshake, mirrors the official app

client.telemetry.listen((t) {
  print('${t.wheelSpeedKph} km/h  ${t.rpm} rpm  gear ${t.gear}');
});
```

## Testing without a bike

`test/parser_test.dart` runs the byte-level parsers against real captured
frame samples (see NOTICE.md for provenance) — including a `0x41` frame that
must decode to `ecuBattery12V == 12.34375` and a `0x03` frame that must
decode to VIN `ML5ER500FADA55558`. Run with:

```bash
cd packages/kawasaki_rideology_ble
dart test
```

If you're validating this against a **2026 Z500 ABS**, capture your own
frames per [`docs/CAPTURE_GUIDE.md`](../../docs/CAPTURE_GUIDE.md) and add
them as additional cases here — that's the fastest way to confirm or correct
the field layout for your specific unit.
