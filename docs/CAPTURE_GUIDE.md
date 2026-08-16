# Capturing and validating a bike's BLE traffic

Use this if you want to confirm the bundled Z500 (ER500F) config against a
**specific unit** — including a 2026 Z500 ABS — or add support for a
different model. No physical bike was available to this project when the
Kawasaki connector was built, so the config here is ported from a validated
external capture, not verified against a 2026 unit directly. This is how
you close that gap.

## What you need

- The bike, parked, with the key on (or however Kawasaki's Rideology app
  normally wakes its BLE radio).
- An Android phone with **Kawasaki's official Rideology app** installed
  and already paired to the bike (you're capturing *its* traffic, so it
  needs to actually talk to the bike first).
- That phone's Developer Options enabled, with **Bluetooth HCI snoop log**
  turned on (Settings → System → Developer options → Bluetooth HCI snoop
  log). This logs every BLE packet the phone sends/receives, regardless of
  which app is using the radio.
- [Wireshark](https://www.wireshark.org/) on a computer to open the log.

This is the same workflow the Home Assistant Kawasaki integration's author
used, and the one documented by the
[Gadgetbridge project](https://codeberg.org/Freeyourgadget/Gadgetbridge/wiki/BT-Protocol-Reverse-Engineering)
for reverse-engineering BLE wearables generally.

## Steps

1. **Enable the snoop log**, then fully restart Bluetooth (toggle it off
   and on) so the log starts clean.
2. **Open Rideology, connect to the bike**, and walk through a few
   screens — dashboard/live view, trip history, settings — so the app
   exercises as many frame types as possible (you want 0x03, 0x40, 0x41,
   0x45, and especially 0x4A to show up).
3. **Pull the log**:
   ```bash
   adb pull /sdcard/Android/data/btsnoop_hci.log ./btsnoop_hci.log
   ```
   (Some OEM builds put it in `/sdcard/btsnoop_hci.log` instead — check
   both if the first path fails.)
4. **Open it in Wireshark** and filter to just this protocol's traffic:
   ```
   btatt
   ```
   Then narrow further to notifications/writes on the characteristic
   handles that match `92faec07-c075-4b7c-a6c2-bbd1d1a150f5` (the service)
   — Wireshark will show the GATT handle-to-UUID mapping from the
   discovery exchange earlier in the capture.
5. **Extract raw frame bytes.** For each `ATT Handle Value Notification` or
   `Write Request` on the relevant handles, copy the value bytes as hex —
   this is exactly what the `samples` map in
   `packages/kawasaki_rideology_ble/test/parser_test.dart` expects.

## Validating what you captured

1. Add your captured frames to the `samples` map in `parser_test.dart`
   (or a scratch script — doesn't need to be a committed test to be
   useful).
2. Run the relevant parser against it, e.g.:
   ```dart
   final t = parseRidingLogMid(hx('4a...your bytes...'));
   print('rpm=${t.rpm} speed=${t.wheelKph} gear=${t.gear}');
   ```
3. **Compare against what the bike's own dash showed at that moment.**
   If you noted "dash said 45 km/h, 3rd gear" when you captured that
   frame, the decoded values should match (or be off by a fixed,
   discoverable scale factor — motorcycle BLE protocols are full of
   these, see the two-interpretation `mode` parameters throughout
   `parsers.dart`).
4. If something's off:
   - Check the 0x40 (`parseInfoConfigFlags`) response from *your* bike —
     if a field's flag is `3` instead of `0`/`1`, your unit genuinely
     doesn't expose that field, and a `null` there is correct, not a bug.
   - If a supported field decodes to a clearly wrong number, the byte
     offset or scale factor may differ for your model/firmware. Open an
     issue with the raw hex and what the dash actually showed — that's
     the exact kind of ground truth needed to fix it.

## What "good enough" looks like

You don't need to validate every field before this is useful — RPM, wheel
speed, gear, and ECU battery voltage are the ones worth confirming first,
since they're the ones a trip tracker actually consumes. Temperature,
trip A/B, and the various torque/lean/ABS fields are nice-to-haves that
can stay unverified longer without blocking anything.
