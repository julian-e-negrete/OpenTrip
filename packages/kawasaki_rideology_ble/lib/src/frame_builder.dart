// Ported from custom_components/kawasaki/kawi_ble5_client.py in
// https://github.com/Zen3515/homeassistant-kawasaki-rideology-ble
// (Apache License 2.0). See /NOTICE.md at the repo root.
//
// These build the exact byte sequences the official Rideology app sends
// during its startup handshake, captured from real app traffic.

import 'dart:typed_data';

import 'protocol_ids.dart';

Uint8List buildSimpleFrame(int frameId, {int tail = 0x00}) {
  return Uint8List.fromList([frameId & 0xFF, 0x00, tail & 0xFF]);
}

Uint8List buildServiceIndicatorFrame() {
  final frame = Uint8List(45)..fillRange(0, 45, 0xFF);
  frame[0] = KawiFrame.serviceIndicator;
  frame[1] = 0x2A;
  frame[2] = 0x01;
  frame[5] = 0x05;
  frame[6] = 0x0C;
  frame[7] = 0x00;
  frame[15] = 0x05;
  frame[16] = 0x0D;
  frame[17] = 0x00;
  frame[25] = 0x05;
  frame[26] = 0x0E;
  frame[27] = 0x00;
  return frame;
}

Uint8List buildVehicleSettingsFrame() {
  final frame = Uint8List(45)..fillRange(0, 45, 0xFF);
  frame[0] = KawiFrame.vehicleSettings;
  frame[1] = 0x2A;
  frame[2] = 0x00;
  frame[5] = 0x05;
  frame[6] = 0x09;
  frame[7] = 0x00;
  return frame;
}

Uint8List buildGeneralSettingsRequestFrame() {
  final frame = Uint8List(15)..fillRange(0, 15, 0xFF);
  frame[0] = KawiFrame.generalSettings;
  frame[1] = 0x0C;
  frame[2] = 0x00;
  frame[3] = 0xFF;
  frame[4] = 0xFF;
  frame[5] = 0x05;
  frame[6] = 0x0A;
  frame[7] = 0x00;
  return frame;
}

Uint8List buildMeterIndicationInitFrame() {
  return Uint8List.fromList([
    KawiFrame.meterIndicationInit,
    0x0C,
    0x00,
    0xFF,
    0xFF,
    0x0A,
    0x08,
    0x01,
    0x78,
    0x03,
    0xE8,
    0x00,
    0xC8,
    0x00,
    0x64,
  ]);
}

Uint8List buildPhoneModelFrame(String model) {
  final data = Uint8List(35);
  data[0] = KawiFrame.phoneModel;
  data[1] = 0x20;
  data[2] = 0x00;
  data[3] = 0xFF;
  data[4] = 0xFF;

  final raw = Uint8List.fromList(model.codeUnits.where((c) => c <= 0x7F).toList());
  const maxChunks = 3;
  const chunkSize = 8;
  for (var chunkIndex = 0; chunkIndex < maxChunks; chunkIndex++) {
    final start = chunkIndex * chunkSize;
    if (start >= raw.length) break;
    final end = (start + chunkSize < raw.length) ? start + chunkSize : raw.length;
    final chunk = raw.sublist(start, end);
    final base = 5 + chunkIndex * 10;
    data[base] = 0x05;
    data[base + 1] = chunkIndex + 1;
    data.setRange(base + 2, base + 2 + chunk.length, chunk);
  }
  return data;
}

/// Frame 0x1B time-sync variant, sent when the bike's clock should be set
/// from the phone (as opposed to a plain settings request).
Uint8List buildTimeSyncFrame({
  required DateTime when,
  int shiftStatus = 1,
  int shiftLevel = 1,
}) {
  final level = shiftLevel.clamp(0, 63);
  final status = shiftStatus.clamp(0, 3);
  return Uint8List.fromList([
    0x1B,
    0x0C,
    0x00,
    0xFF,
    0xFF,
    0x05,
    0x4A,
    0x01,
    ((status & 0x03) << 6) | (level & 0x3F),
    when.day & 0x3F,
    when.month & 0x0F,
    (when.year - 2000) & 0xFF,
    when.hour & 0x1F,
    when.minute & 0x3F,
    when.second & 0x3F,
  ]);
}
