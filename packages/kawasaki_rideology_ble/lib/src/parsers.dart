// Ported from custom_components/kawasaki/kawi_ble5_client.py in
// https://github.com/Zen3515/homeassistant-kawasaki-rideology-ble
// (Apache License 2.0). See /NOTICE.md at the repo root.
//
// Byte-for-byte port of the field offsets, masks, and scaling factors that
// project derived from real captured Rideology BLE traffic. Where the
// original code carries two candidate interpretations of a field (the bike
// firmware/app has shipped inconsistent scaling across versions), that
// ambiguity is preserved here via the same `mode` parameters rather than
// silently picking one.

import 'protocol_ids.dart';

int? u8(List<int> data, int idx) => idx < data.length ? data[idx] & 0xFF : null;

/// Picks whichever of two interpretations of a raw value looks plausible.
int autoChoose(int raw, int scaled, {int high = 20000, int maxOk = 15000}) {
  if (raw > high && scaled <= maxOk) return scaled;
  if (raw == 0 && scaled > 0) return scaled;
  return raw;
}

num? chooseInRange(num? a, num? b, num low, num high) {
  if (a != null && a >= low && a <= high) return a;
  if (b != null && b >= low && b <= high) return b;
  return a ?? b;
}

// ---------------------------------------------------------------------
// Frame 0x03 — model info (VIN)
// ---------------------------------------------------------------------

class ModelInfo {
  final String? modelName;
  final String? vin;
  final String? vinPart71;
  final String? vinPart72;
  final String? vinPart73;

  const ModelInfo({this.modelName, this.vin, this.vinPart71, this.vinPart72, this.vinPart73});
}

ModelInfo parseModelInfo(List<int> data) {
  if (data.length < 8) return const ModelInfo();

  final tlvChunks = <int, String>{};
  var i = 5;
  while (i + 2 < data.length) {
    if (data[i] != 0x02) {
      i += 1;
      continue;
    }
    final tag = data[i + 1] & 0xFF;
    var end = i + 2;
    while (end < data.length && data[end] != 0x02 && data[end] != 0xFF) {
      end += 1;
    }
    final chunk = String.fromCharCodes(
      data.sublist(i + 2, end).where((b) => b != 0x00),
    ).trim();
    if (chunk.isNotEmpty) tlvChunks[tag] = chunk;
    i = end;
  }

  final modelCode = tlvChunks[0x71];
  final serialCode = tlvChunks[0x72];
  final suffixCode = tlvChunks[0x73];

  String? modelName = modelCode;
  String? vin;
  if (modelCode != null && serialCode != null) {
    final candidate = '$modelCode$serialCode${suffixCode ?? ''}'.trim();
    if (candidate.length == 13 || candidate.length == 17) vin = candidate;
  }

  if (modelName == null && data.length >= 33) {
    final stitched = <int>[
      ...data.sublist(2, 8),
      ...data.sublist(8, 14),
      ...data.sublist(27, 33),
    ];
    final stitchedAscii = String.fromCharCodes(
      stitched.where((b) => b != 0x00 && b != 0xFF),
    ).trim();
    modelName = stitchedAscii.isEmpty ? null : stitchedAscii;
    if (vin == null && (stitchedAscii.length == 13 || stitchedAscii.length == 17)) {
      vin = stitchedAscii;
    }
  }

  return ModelInfo(
    modelName: modelName,
    vin: vin,
    vinPart71: modelCode,
    vinPart72: serialCode,
    vinPart73: suffixCode,
  );
}

// ---------------------------------------------------------------------
// Shared "0x05 <chunk_id> <8 ascii bytes>" repeating text-chunk format,
// used inside 0x0B, 0x20 (phone-model ACK), and 0x30 (text-chunk status).
// ---------------------------------------------------------------------

(String?, String?) parseTextChunksBy0x05(List<int> data, {int startIndex = 5}) {
  final chunks = <int, String>{};
  var i = startIndex;
  while (i + 1 < data.length) {
    if (data[i] != 0x05) {
      i += 1;
      continue;
    }
    final chunkId = data[i + 1] & 0xFF;
    final end = (i + 10 < data.length) ? i + 10 : data.length;
    final chunkText = String.fromCharCodes(
      data.sublist(i + 2, end).where((b) => b != 0x00 && b != 0xFF),
    ).trim();
    if (chunkText.isNotEmpty) chunks[chunkId] = chunkText;
    i += 10;
  }
  final orderedIds = chunks.keys.toList()..sort();
  if (orderedIds.isEmpty) return (null, null);
  final chunkIds = orderedIds
      .map((id) => '0x${id.toRadixString(16).padLeft(2, '0').toUpperCase()}')
      .join(',');
  final text = orderedIds.map((id) => chunks[id]).join();
  return (text.isEmpty ? null : text, chunkIds);
}

// ---------------------------------------------------------------------
// Frame 0x20 — generic ACK
// ---------------------------------------------------------------------

class AckFrame {
  final int? ackCommand;
  final String? ackCommandName;
  final int? resultCode;
  final String? resultText;
  final String? phoneModelText;
  final String? phoneModelChunkIds;
  final int? meterIndicationBlockId;
  final int? meterIndicationCommandId;
  final int? meterIndicationParam1;
  final int? meterIndicationParam2;
  final int? meterIndicationParam3;
  final int? meterIndicationParam4;

  const AckFrame({
    this.ackCommand,
    this.ackCommandName,
    this.resultCode,
    this.resultText,
    this.phoneModelText,
    this.phoneModelChunkIds,
    this.meterIndicationBlockId,
    this.meterIndicationCommandId,
    this.meterIndicationParam1,
    this.meterIndicationParam2,
    this.meterIndicationParam3,
    this.meterIndicationParam4,
  });
}

AckFrame parseAck(List<int> data) {
  int? ackCommand;
  int? resultCode;
  String? phoneModelText;
  String? phoneModelChunkIds;
  int? blockId, commandId, p1, p2, p3, p4;

  if (data.length > 3) ackCommand = data[3] & 0xFF;
  if (data.length > 7) {
    resultCode = data[7] & 0xFF;
  } else if (data.length > 4) {
    resultCode = data[4] & 0xFF;
  }

  if (ackCommand == KawiFrame.phoneModel) {
    final (text, chunkIds) = parseTextChunksBy0x05(data, startIndex: 5);
    phoneModelText = text;
    phoneModelChunkIds = chunkIds;
  }

  if (ackCommand == KawiFrame.meterIndicationInit) {
    if (data.length > 5) blockId = data[5] & 0xFF;
    if (data.length > 6) commandId = data[6] & 0xFF;
    if (data.length > 8) p1 = data[8] & 0xFF;
    if (data.length > 10) p2 = ((data[9] & 0xFF) << 8) | (data[10] & 0xFF);
    if (data.length > 12) p3 = ((data[11] & 0xFF) << 8) | (data[12] & 0xFF);
    if (data.length > 14) p4 = ((data[13] & 0xFF) << 8) | (data[14] & 0xFF);
  }

  return AckFrame(
    ackCommand: ackCommand,
    ackCommandName: ackCommand == null ? null : frameName(ackCommand),
    resultCode: resultCode,
    resultText: resultCode == null ? null : ackResultText(resultCode),
    phoneModelText: phoneModelText,
    phoneModelChunkIds: phoneModelChunkIds,
    meterIndicationBlockId: blockId,
    meterIndicationCommandId: commandId,
    meterIndicationParam1: p1,
    meterIndicationParam2: p2,
    meterIndicationParam3: p3,
    meterIndicationParam4: p4,
  );
}

// ---------------------------------------------------------------------
// Frame 0x30 — status report (block result or text chunks)
// ---------------------------------------------------------------------

class StatusReport {
  final String statusType; // 'block_result' | 'text_chunks' | 'generic'
  final int? blockId;
  final String? blockName;
  final int? resultCode;
  final String? resultText;
  final String? text;
  final String? chunkIds;

  const StatusReport({
    required this.statusType,
    this.blockId,
    this.blockName,
    this.resultCode,
    this.resultText,
    this.text,
    this.chunkIds,
  });
}

StatusReport parseStatusReport(List<int> data) {
  final payloadLen = data.length > 1 ? data[1] & 0xFF : null;

  if (data.length >= 8 && payloadLen == 0x0C && data[5] == 0x05) {
    final blockId = data[6] & 0xFF;
    final resultCode = data[7] & 0xFF;
    return StatusReport(
      statusType: 'block_result',
      blockId: blockId,
      blockName: frameName(blockId),
      resultCode: resultCode,
      resultText: ackResultText(resultCode),
    );
  }

  if (data.length >= 35 && payloadLen == 0x20) {
    final chunks = <int, String>{};
    var i = 5;
    while (i + 9 < data.length) {
      if (data[i] != 0x05) {
        i += 1;
        continue;
      }
      final chunkId = data[i + 1] & 0xFF;
      final chunk = String.fromCharCodes(
        data.sublist(i + 2, i + 10).where((b) => b != 0x00 && b != 0xFF),
      ).trim();
      if (chunk.isNotEmpty) chunks[chunkId] = chunk;
      i += 10;
    }
    final orderedIds = chunks.keys.toList()..sort();
    final text = orderedIds.map((id) => chunks[id]).join();
    return StatusReport(
      statusType: 'text_chunks',
      text: text.isEmpty ? null : text,
      chunkIds: orderedIds.isEmpty
          ? null
          : orderedIds
              .map((id) => '0x${id.toRadixString(16).padLeft(2, '0').toUpperCase()}')
              .join(','),
    );
  }

  int? blockId, blockValue;
  if (data.length > 7 && data[5] == 0x05) {
    blockId = data[6] & 0xFF;
    blockValue = data[7] & 0xFF;
  }
  return StatusReport(statusType: 'generic', blockId: blockId, resultCode: blockValue);
}

// ---------------------------------------------------------------------
// Frame 0x08 — meter indication init (mostly useful to confirm the
// startup handshake landed; the official app always sends the same
// "default profile" parameters).
// ---------------------------------------------------------------------

class MeterIndicationInit {
  final int? blockId;
  final int? commandId;
  final bool? enabled;
  final int? param1, param2, param3, param4;
  final bool isDefaultProfile;

  const MeterIndicationInit({
    this.blockId,
    this.commandId,
    this.enabled,
    this.param1,
    this.param2,
    this.param3,
    this.param4,
    this.isDefaultProfile = false,
  });
}

MeterIndicationInit parseMeterIndicationInit(List<int> data) {
  if (data.length < 8) return const MeterIndicationInit();
  final blockId = data[5] & 0xFF;
  final commandId = data[6] & 0xFF;
  final enabled = (data[7] & 0xFF) == 0x01;
  final p1 = data.length > 8 ? data[8] & 0xFF : null;
  final p2 = data.length > 10 ? ((data[9] & 0xFF) << 8) | (data[10] & 0xFF) : null;
  final p3 = data.length > 12 ? ((data[11] & 0xFF) << 8) | (data[12] & 0xFF) : null;
  final p4 = data.length > 14 ? ((data[13] & 0xFF) << 8) | (data[14] & 0xFF) : null;
  final isDefault = (data[1] & 0xFF) == 0x0C &&
      blockId == 0x0A &&
      commandId == 0x08 &&
      enabled &&
      p1 == 120 &&
      p2 == 1000 &&
      p3 == 200 &&
      p4 == 100;
  return MeterIndicationInit(
    blockId: blockId,
    commandId: commandId,
    enabled: enabled,
    param1: p1,
    param2: p2,
    param3: p3,
    param4: p4,
    isDefaultProfile: isDefault,
  );
}

// ---------------------------------------------------------------------
// Frame 0x0B — phone/client model text
// ---------------------------------------------------------------------

(String?, String?) parsePhoneModel(List<int> data) => parseTextChunksBy0x05(data, startIndex: 5);

// ---------------------------------------------------------------------
// Frame 0x40 — MC info config (per-bike support/scaling flags)
// ---------------------------------------------------------------------

class InfoConfigFlags {
  final Map<String, int> flags;
  final bool configValid;
  final List<String> supportedFields;
  final List<String> unsupportedFields;

  const InfoConfigFlags({
    required this.flags,
    required this.configValid,
    required this.supportedFields,
    required this.unsupportedFields,
  });

  static const InfoConfigFlags empty = InfoConfigFlags(
    flags: {},
    configValid: false,
    supportedFields: [],
    unsupportedFields: [],
  );
}

InfoConfigFlags parseInfoConfigFlags(List<int> data) {
  if (data.length < 35) return InfoConfigFlags.empty;

  final flags = <String, int>{};
  for (final (name, index, mask, shift) in infoConfigFieldLayout) {
    flags[name] = (data[index] & mask) >> shift;
  }

  bool groupReady(int aIdx, int bIdx, int flagIdx) {
    final aRaw = data[aIdx] & 0xFF;
    final bRaw = data[bIdx] & 0xFF;
    final flag = data[flagIdx] & 0xFF;
    return (aRaw != 0xFF || bRaw != 0xFF) && ((flag & 0x01) == 0);
  }

  final retryRequired = groupReady(5, 6, 14) || groupReady(15, 16, 24) || groupReady(25, 26, 34);

  final supported = <String>[];
  final unsupported = <String>[];
  flags.forEach((name, mode) {
    if (mode == 0 || mode == 1) {
      supported.add(name);
    } else if (mode == 3) {
      unsupported.add(name);
    }
  });

  return InfoConfigFlags(
    flags: flags,
    configValid: !retryRequired,
    supportedFields: supported,
    unsupportedFields: unsupported,
  );
}

// ---------------------------------------------------------------------
// Frame 0x1D — common-service config (maintenance reminder capability),
// also embedded inside the EV/HEV variant of frame 0x42.
// ---------------------------------------------------------------------

class CommonServiceConfigFlags {
  final Map<String, int> flags;
  final bool configValid;
  final bool kawasakiServiceSupported;
  final bool riderSettingSupported;
  final bool oilChangeSupported;
  final int supportedCount;
  final int unsupportedCount;

  const CommonServiceConfigFlags({
    required this.flags,
    required this.configValid,
    required this.kawasakiServiceSupported,
    required this.riderSettingSupported,
    required this.oilChangeSupported,
    required this.supportedCount,
    required this.unsupportedCount,
  });
}

const _commonServiceCapabilityFields = {
  'kawasaki_service_setting_capability',
  'user_setting_capability',
  'oil_change_setting_capability',
};

CommonServiceConfigFlags? parseCommonServiceConfigFlags(List<int> data) {
  if (data.length < 15) return null;

  final flags = <String, int>{};
  var supportedCount = 0, unsupportedCount = 0;
  for (final (name, index, mask, shift) in commonServiceConfigFieldLayout) {
    final mode = (data[index] & mask) >> shift;
    flags[name] = mode;
    final isSupported = _commonServiceCapabilityFields.contains(name) ? (mode == 0 || mode == 1) : mode == 0;
    if (isSupported) {
      supportedCount += 1;
    } else {
      unsupportedCount += 1;
    }
  }

  final retryRequired = (((data[5] & 0xFF) != 0xFF) || ((data[6] & 0xFF) != 0xFF)) && ((data[14] & 0x01) == 0);

  bool groupSupported(String capabilityField, List<String> zeroFields) {
    final cap = flags[capabilityField];
    if (cap != 0 && cap != 1) return false;
    return zeroFields.every((f) => flags[f] == 0);
  }

  return CommonServiceConfigFlags(
    flags: flags,
    configValid: !retryRequired,
    kawasakiServiceSupported: groupSupported('kawasaki_service_setting_capability', [
      'kawasaki_service_notify',
      'kawasaki_service_month',
      'kawasaki_service_day',
      'kawasaki_service_year',
      'kawasaki_service_distance',
    ]),
    riderSettingSupported: groupSupported('user_setting_capability', [
      'user_setting_notify',
      'user_setting_month',
      'user_setting_day',
      'user_setting_year',
      'user_setting_distance',
    ]),
    oilChangeSupported: groupSupported('oil_change_setting_capability', [
      'oil_change_notify',
      'oil_change_month',
      'oil_change_day',
      'oil_change_year',
      'oil_change_distance',
    ]),
    supportedCount: supportedCount,
    unsupportedCount: unsupportedCount,
  );
}

// ---------------------------------------------------------------------
// Frame 0x42 — EMC info (format varies by model/frame length)
// ---------------------------------------------------------------------

class EmcInfo {
  final String packetType;
  final CommonServiceConfigFlags? serviceConfigLike;
  final int? blockId;
  final int? blockValue;
  final String? text;
  final String? chunkIds;

  const EmcInfo({required this.packetType, this.serviceConfigLike, this.blockId, this.blockValue, this.text, this.chunkIds});
}

EmcInfo parseEmcInfo(List<int> data) {
  if (data.length == 3 && data[1] == 0x00) {
    return const EmcInfo(packetType: 'request_command');
  }
  if (data.length >= 15 && (data[1] & 0xFF) == 0x0C) {
    final cfg = parseCommonServiceConfigFlags(data);
    return EmcInfo(packetType: 'service_indicator_config_like', serviceConfigLike: cfg);
  }
  if (data.length >= 8 && data[5] == 0x05) {
    return EmcInfo(packetType: 'block_result', blockId: data[6] & 0xFF, blockValue: data[7] & 0xFF);
  }
  final (text, chunkIds) = parseTextChunksBy0x05(data, startIndex: 5);
  if (text != null || chunkIds != null) {
    return EmcInfo(packetType: 'text_chunks', text: text, chunkIds: chunkIds);
  }
  return const EmcInfo(packetType: 'raw_or_unknown');
}

// ---------------------------------------------------------------------
// Frame 0x41 — MC info (odometer, trip, battery, fuel)
// ---------------------------------------------------------------------

class McInfo {
  final double? totalFuelConsumed;
  final double? ecuBattery12V;
  final int? odometer;
  final int? fuelGauge;
  final double? averageFuelMileage;
  final double? meterBattery12V;
  final double? tripA;
  final double? tripB;
  final int? averageSpeed;
  final int? outerAirTemperature;
  final int? rangeSymbol;
  final int? range;
  final double? fuelConsumption;
  final int? totalTime;

  const McInfo({
    this.totalFuelConsumed,
    this.ecuBattery12V,
    this.odometer,
    this.fuelGauge,
    this.averageFuelMileage,
    this.meterBattery12V,
    this.tripA,
    this.tripB,
    this.averageSpeed,
    this.outerAirTemperature,
    this.rangeSymbol,
    this.range,
    this.fuelConsumption,
    this.totalTime,
  });
}

/// `gate(flag, expected)` mirrors the app's per-field support check: a
/// field is decoded only if its 0x40-flag equals `expected` (usually 0 =
/// "supported"), or if we don't know the flag at all (opportunistic parse).
bool _gate(Map<String, int>? infoFlags, String flag, int expected) {
  final value = infoFlags?[flag];
  return value == null || value == expected;
}

McInfo parseMcInfo(List<int> data, {Map<String, int>? infoConfigFlags, Map<String, bool>? supportedFields}) {
  double? totalFuelConsumed;
  if (data.length > 10 && _gate(infoConfigFlags, 'total_fuel_consumed', 0)) {
    final raw = ((data[7] & 0xFF) << 24) | ((data[8] & 0xFF) << 16) | ((data[9] & 0xFF) << 8) | (data[10] & 0xFF);
    totalFuelConsumed = raw * 0.01;
  }

  double? ecuBattery12v;
  if (data.length > 14 && _gate(infoConfigFlags, 'ecu_battery12V', 0)) {
    ecuBattery12v = ((data[14] & 0xFF) * 20.0) / 256.0;
  }

  int? odometer;
  if (data.length > 29 && _gate(infoConfigFlags, 'odometer', 0)) {
    odometer = ((data[27] & 0x0F) << 16) | ((data[28] & 0xFF) << 8) | (data[29] & 0xFF);
  }

  int? fuelGauge;
  if (data.length > 30 && _gate(infoConfigFlags, 'fuel_gauge', 0)) {
    fuelGauge = data[30] & 0x0F;
  }

  double? averageFuelMileage;
  if (data.length > 33 && _gate(infoConfigFlags, 'average_fuel_mileage', 0)) {
    final raw = ((data[32] & 0x03) << 8) | (data[33] & 0xFF);
    averageFuelMileage = raw * 0.1;
  }

  double? meterBattery12v;
  if (data.length > 34 && _gate(infoConfigFlags, 'meter_battery12V', 0)) {
    meterBattery12v = (data[34] & 0xFF) * 0.1;
  }

  double? tripA;
  if (data.length > 39 && _gate(infoConfigFlags, 'tripA', 0)) {
    final raw = ((data[37] & 0x01) << 16) | ((data[38] & 0xFF) << 8) | (data[39] & 0xFF);
    tripA = raw * 0.1;
  }

  double? tripB;
  if (data.length > 42 && _gate(infoConfigFlags, 'tripB', 0)) {
    final raw = ((data[40] & 0x01) << 16) | ((data[41] & 0xFF) << 8) | (data[42] & 0xFF);
    tripB = raw * 0.1;
  }

  int? averageSpeed;
  if (data.length > 43 && _gate(infoConfigFlags, 'average_speed', 0)) {
    averageSpeed = data[43] & 0xFF;
  }

  int? outerAirTemperature;
  if (data.length > 44 && _gate(infoConfigFlags, 'outer_air_temperature', 0)) {
    outerAirTemperature = (data[44] & 0xFF) - 60;
  }

  int? rangeSymbol;
  if (data.length > 47 && _gate(infoConfigFlags, 'range_symbol', 0)) {
    rangeSymbol = (data[47] & 0x30) >> 4;
  }

  int? range;
  if (data.length > 48 && _gate(infoConfigFlags, 'range', 0)) {
    range = ((data[47] & 0x03) << 8) | (data[48] & 0xFF);
  }

  double? fuelConsumption;
  if (data.length > 50 && _gate(infoConfigFlags, 'fuel_consumption', 0)) {
    final raw = ((data[49] & 0x03) << 8) | (data[50] & 0xFF);
    fuelConsumption = raw * 0.1;
  }

  int? totalTime;
  if (data.length > 52 && _gate(infoConfigFlags, 'total_time', 0)) {
    totalTime = ((data[51] & 0x1F) << 8) | (data[52] & 0xFF);
  }

  // Matches the upstream semantics exactly: a field is only forced to null
  // when the model config *explicitly* marks it unsupported (`false`).
  // Absent from the map, or explicitly `true`, both mean "keep whatever
  // the byte-level gate computed" — this is a denylist, not an allowlist.
  bool keep(String key) => supportedFields == null || supportedFields[key] != false;

  return McInfo(
    totalFuelConsumed: keep('total_fuel_consumed') ? totalFuelConsumed : null,
    ecuBattery12V: keep('ecu_battery12V') ? ecuBattery12v : null,
    odometer: keep('odometer') ? odometer : null,
    fuelGauge: keep('fuel_gauge') ? fuelGauge : null,
    averageFuelMileage: keep('average_fuel_mileage') ? averageFuelMileage : null,
    meterBattery12V: keep('meter_battery12V') ? meterBattery12v : null,
    tripA: keep('tripA') ? tripA : null,
    tripB: keep('tripB') ? tripB : null,
    averageSpeed: keep('average_speed') ? averageSpeed : null,
    outerAirTemperature: keep('outer_air_temperature') ? outerAirTemperature : null,
    rangeSymbol: keep('range_symbol') ? rangeSymbol : null,
    range: keep('range') ? range : null,
    fuelConsumption: keep('fuel_consumption') ? fuelConsumption : null,
    totalTime: keep('total_time') ? totalTime : null,
  );
}

// ---------------------------------------------------------------------
// Frame 0x45 — riding log ext (temperatures, tire pressure, odometer)
// ---------------------------------------------------------------------

class RidingLogExt {
  final double? totalDistanceTraveled;
  final double? engineFuelRate;
  final int? waterTemperature;
  final int? oilTemperature;
  final int? inletAirTemperature;
  final double? instantFuelConsumption;
  final double? tirePressureFr;
  final double? tirePressureRr;
  final int? airPressureDropFr;
  final int? airPressureDropRr;
  final int? lowBatteryVoltageFr;
  final int? lowBatteryVoltageRr;
  final int? odometer;

  const RidingLogExt({
    this.totalDistanceTraveled,
    this.engineFuelRate,
    this.waterTemperature,
    this.oilTemperature,
    this.inletAirTemperature,
    this.instantFuelConsumption,
    this.tirePressureFr,
    this.tirePressureRr,
    this.airPressureDropFr,
    this.airPressureDropRr,
    this.lowBatteryVoltageFr,
    this.lowBatteryVoltageRr,
    this.odometer,
  });
}

RidingLogExt parseRidingLogExt(List<int> data, {Map<String, int>? infoConfigFlags, Map<String, bool>? supportedFields}) {
  double? totalDistanceTraveled;
  if (data.length > 10 && _gate(infoConfigFlags, 'total_distance_traveled', 0)) {
    final raw = ((data[7] & 0xFF) << 24) | ((data[8] & 0xFF) << 16) | ((data[9] & 0xFF) << 8) | (data[10] & 0xFF);
    totalDistanceTraveled = raw * 0.1;
  }

  double? engineFuelRate;
  if (data.length > 12 && _gate(infoConfigFlags, 'engine_fuel_rate', 0)) {
    final raw = ((data[11] & 0xFF) << 8) | (data[12] & 0xFF);
    engineFuelRate = raw * 0.02;
  }

  int? waterTemperature;
  if (data.length > 17 && _gate(infoConfigFlags, 'engine_water_temperature', 1)) {
    final raw = data[17] & 0xFF;
    waterTemperature = raw == 0xFF ? null : raw - 40;
  }

  int? oilTemperature;
  if (data.length > 19 && _gate(infoConfigFlags, 'engine_oil_temperature', 1)) {
    final raw = data[19] & 0xFF;
    oilTemperature = raw == 0xFF ? null : raw - 60;
  }

  int? inletAirTemperature;
  if (data.length > 20 && _gate(infoConfigFlags, 'inlet_air_temperature', 1)) {
    final raw = data[20] & 0xFF;
    inletAirTemperature = raw == 0xFF ? null : raw - 40;
  }

  double? instantFuelConsumption;
  if (data.length > 28 && _gate(infoConfigFlags, 'instant_fuel_consumption', 0)) {
    final raw = ((data[27] & 0x03) << 8) | (data[28] & 0xFF);
    instantFuelConsumption = raw * 0.1;
  }

  double? tireFr, tireRr;
  int? dropFr, dropRr, lowBattFr, lowBattRr;
  if (data.length > 49) {
    final tpmsDisabled = (data[45] & 0x01) != 0 || (data[46] & 0x01) != 0;
    final frontRaw = data[47] & 0xFF;
    final rearRaw = data[48] & 0xFF;
    if (!tpmsDisabled && frontRaw != 0xFF) tireFr = (frontRaw * 1.373) + 100.0;
    if (!tpmsDisabled && rearRaw != 0xFF) tireRr = (rearRaw * 1.373) + 100.0;
    if (!tpmsDisabled) {
      final warn = data[49] & 0xFF;
      dropFr = warn & 0x01;
      dropRr = (warn >> 1) & 0x01;
      lowBattFr = (warn >> 2) & 0x01;
      lowBattRr = (warn >> 3) & 0x01;
    }
  }

  int? odometer;
  if (data.length > 59 && _gate(infoConfigFlags, 'odometer', 0)) {
    odometer = ((data[57] & 0x0F) << 16) | ((data[58] & 0xFF) << 8) | (data[59] & 0xFF);
  }

  bool keep(String key) => supportedFields == null || supportedFields[key] != false;

  return RidingLogExt(
    totalDistanceTraveled: keep('total_distance_traveled') ? totalDistanceTraveled : null,
    engineFuelRate: keep('engine_fuel_rate') ? engineFuelRate : null,
    waterTemperature: keep('water_temperature') ? waterTemperature : null,
    oilTemperature: keep('oil_temperature') ? oilTemperature : null,
    inletAirTemperature: keep('inlet_air_temperature') ? inletAirTemperature : null,
    instantFuelConsumption: keep('instant_fuel_consumption') ? instantFuelConsumption : null,
    tirePressureFr: keep('tire_pressure_fr') ? tireFr : null,
    tirePressureRr: keep('tire_pressure_rr') ? tireRr : null,
    airPressureDropFr: keep('air_pressure_drop_fr') ? dropFr : null,
    airPressureDropRr: keep('air_pressure_drop_rr') ? dropRr : null,
    lowBatteryVoltageFr: keep('low_battery_voltage_fr') ? lowBattFr : null,
    lowBatteryVoltageRr: keep('low_battery_voltage_rr') ? lowBattRr : null,
    odometer: keep('odometer') ? odometer : null,
  );
}

// ---------------------------------------------------------------------
// Frame 0x4A — riding log mid: THE live-telemetry frame. Streams
// continuously while the bike is running.
// ---------------------------------------------------------------------

class RidingLogMid {
  final double? statusFuelInjection;
  final int? rpm;
  final int? wheelKph;
  final int? gear;
  final double? throttle;
  final double? leanDeg;
  final double? accelG;
  final int? wheelieFlag;
  final double? wheelieAngle;
  final int? tcsLevelHb;
  final int? tcsLevelLb;
  final int? riderTorqueRequest;
  final int? engineTorqueRequest;
  final int? engineTorqueActual;
  final int? absCplInspMode;
  final int? absSystemError;
  final int? absFrontStatus;
  final int? absRearStatus;
  final double? frontBrakePressure;
  final int? absTarget;
  final int? absIndicator;
  final int? switchingInfo;

  const RidingLogMid({
    this.statusFuelInjection,
    this.rpm,
    this.wheelKph,
    this.gear,
    this.throttle,
    this.leanDeg,
    this.accelG,
    this.wheelieFlag,
    this.wheelieAngle,
    this.tcsLevelHb,
    this.tcsLevelLb,
    this.riderTorqueRequest,
    this.engineTorqueRequest,
    this.engineTorqueActual,
    this.absCplInspMode,
    this.absSystemError,
    this.absFrontStatus,
    this.absRearStatus,
    this.frontBrakePressure,
    this.absTarget,
    this.absIndicator,
    this.switchingInfo,
  });
}

int? parseRpm(List<int> data, String mode) {
  if (data.length < 13) return null;
  final raw0 = ((data[11] & 0x7F) << 8) | (data[12] & 0xFF);
  final scaledQuarter = ((((data[11] & 0xFF) << 8) | (data[12] & 0xFF)) * 0.25).toInt();
  if (mode == 'raw') return raw0;
  if (mode == 'quarter') return scaledQuarter;
  return autoChoose(raw0, scaledQuarter);
}

int? parseWheelSpeedKph(List<int> data, String mode) {
  if (data.length < 11) return null;
  final raw = ((data[9] & 0xFF) << 8) | (data[10] & 0xFF);
  final scaled = (raw * 0.01220703125).toInt();
  final raw1 = ((data[9] & 0x01) << 8) | (data[10] & 0xFF);
  if (mode == 'raw') return raw;
  if (mode == 'scaled') return scaled;
  if (mode == 'raw1') return raw1;
  if (scaled >= 0 && scaled <= 300) return scaled;
  if (raw1 >= 0 && raw1 <= 300) return raw1;
  return scaled;
}

(double?, double?, double?) _parseStatusFuelInjection(List<int> data, String mode) {
  if (data.length <= 8) return (null, null, null);
  final raw = ((data[7] & 0xFF) << 8) | (data[8] & 0xFF);
  final rawVal = raw * 1e-4;
  final scaledVal = rawVal * 100.0 / 140.0;
  if (mode == 'scale_a') return (rawVal, rawVal, scaledVal);
  if (mode == 'scale_b') return (scaledVal, rawVal, scaledVal);
  return (chooseInRange(rawVal, scaledVal, 0.0, 1.0)?.toDouble(), rawVal, scaledVal);
}

(double?, double?, double?) _parseThrottle(List<int> data, String mode) {
  if (data.length <= 14) return (null, null, null);
  final rider = (data[14] & 0xFF) * 0.78125;
  final mecha = (data[14] & 0xFF) * 0.3921568627;
  if (mode == 'rider') return (rider, rider, mecha);
  if (mode == 'mecha') return (mecha, rider, mecha);
  return (chooseInRange(mecha, rider, 0.0, 100.0)?.toDouble(), rider, mecha);
}

double? _parseAccel(List<int> data, String mode) {
  if (data.length <= 18) return null;
  final raw = ((data[17] & 0x01) << 8) | (data[18] & 0xFF);
  final a = raw * 0.01 - 2.0;
  final b = raw * 0.01;
  if (mode == 'minus2') return a;
  if (mode == 'raw') return b;
  return chooseInRange(a, b, -5.0, 5.0)?.toDouble();
}

double? _parseLean(List<int> data, String mode) {
  if (data.length <= 20) return null;
  final raw0 = ((data[19] & 0x07) << 8) | (data[20] & 0xFF);
  final raw1 = ((data[19] & 0x0F) << 8) | (data[20] & 0xFF);
  final leanA = raw0 * 0.1953125 - 100.0;
  final leanB = raw1 * 0.1;
  if (mode == 'minus100') return leanA;
  if (mode == 'raw') return leanB;
  return chooseInRange(leanA, leanB, -90.0, 90.0)?.toDouble();
}

(int?, double?) _parseWheelie(List<int> data, String mode) {
  final wheelieFlag = data.length > 21 ? data[21] & 0x03 : null;
  if (data.length <= 23) return (wheelieFlag, null);
  final raw0 = ((data[22] & 0x07) << 8) | (data[23] & 0xFF);
  final raw1 = ((data[22] & 0x0F) << 8) | (data[23] & 0xFF);
  final angA = raw0 * 0.09765625;
  final angB = raw1 * 0.1;
  if (mode == 'scale09765625') return (wheelieFlag, angA);
  if (mode == 'scale0.1') return (wheelieFlag, angB);
  return (wheelieFlag, chooseInRange(angA, angB, 0.0, 60.0)?.toDouble());
}

(int?, int?) _parseTcsLevels(List<int> data) {
  if (data.length <= 24) return (null, null);
  return ((data[24] & 0xF0) >> 4, data[24] & 0x0F);
}

(int?, int?, int?) _parseTorquePair(List<int> data, int idxHi, int idxLo, String mode) {
  if (data.length <= idxLo) return (null, null, null);
  final raw0 = ((data[idxHi] & 0x3F) << 8) | (data[idxLo] & 0xFF);
  final raw1 = ((data[idxHi] & 0x0F) << 8) | (data[idxLo] & 0xFF);
  final val0 = (raw0 * 0.2).toInt();
  final val1 = raw1;
  if (mode == 'scaled') return (val0, val0, val1);
  if (mode == 'raw') return (val1, val0, val1);
  return (autoChoose(val1, val0, high: 5000, maxOk: 2000), val0, val1);
}

(int?, int?, int?, int?) _parseAbsStatuses(List<int> data) {
  if (data.length <= 37) return (null, null, null, null);
  final b35 = u8(data, 35), b36 = u8(data, 36), b37 = u8(data, 37);
  if (b35 == null || b36 == null || b37 == null || b35 == 0xFF || b36 == 0xFF) {
    return (null, null, null, null);
  }
  return ((b37 & 0x10) >> 4, (b37 & 0x0C) >> 2, b37 & 0x01, (b37 & 0x02) >> 1);
}

double? _parseFrontBrakePressure(List<int> data) {
  if (data.length <= 39) return null;
  final b35 = u8(data, 35), b36 = u8(data, 36), b39 = u8(data, 39);
  if (b35 == null || b36 == null || b39 == null || b35 == 0xFF || b36 == 0xFF || b39 == 0xFF) {
    return null;
  }
  return b39 * 0.1953125;
}

(int?, int?, int?) _parseAbsTargetIndicator(List<int> data) {
  if (data.length <= 48) return (null, null, null);
  final b45 = u8(data, 45), b46 = u8(data, 46), b47 = u8(data, 47), b48 = u8(data, 48);
  if (b45 == null || b46 == null || b47 == null) return (null, null, null);
  int? absTarget, absIndicator, switchingInfo;
  if (b45 != 0xFF && b46 != 0xFF && (b47 & 0x07) != 0) {
    absTarget = (b47 & 0xE0) >> 5;
  }
  if (b45 != 0xFF && b46 != 0xFF) {
    absIndicator = b47 & 0x07;
    if (b48 != null) switchingInfo = b48 & 0x01;
  }
  return (absTarget, absIndicator, switchingInfo);
}

RidingLogMid parseRidingLogMid(
  List<int> data, {
  String rpmMode = 'auto',
  String wheelMode = 'auto',
  Map<String, bool>? supportedFields,
}) {
  final rpm = parseRpm(data, rpmMode);
  final wheelKph = parseWheelSpeedKph(data, wheelMode);
  final gear = data.length > 13 ? data[13] & 0x0F : null;

  // Using `.$1` (the record's first field) rather than destructuring every
  // position avoids re-declaring a discard variable name multiple times in
  // this scope, which some Dart SDK versions reject.
  final statusFuelInjection = _parseStatusFuelInjection(data, 'auto').$1;
  final throttle = _parseThrottle(data, 'auto').$1;
  final accel = _parseAccel(data, 'auto');
  final lean = _parseLean(data, 'auto');
  final (wheelieFlag, wheelieAngle) = _parseWheelie(data, 'auto');
  final (tcsHb, tcsLb) = _parseTcsLevels(data);
  final riderTorque = _parseTorquePair(data, 27, 28, 'auto').$1;
  final engineTorqueReq = _parseTorquePair(data, 29, 30, 'auto').$1;
  final engineTorqueAct = _parseTorquePair(data, 31, 32, 'auto').$1;
  final (absCpl, absErr, absFront, absRear) = _parseAbsStatuses(data);
  final frontBrake = _parseFrontBrakePressure(data);
  final (absTarget, absIndicator, switchingInfo) = _parseAbsTargetIndicator(data);

  bool keep(String key) => supportedFields == null || supportedFields[key] != false;

  return RidingLogMid(
    statusFuelInjection: keep('status_fuel_injection') ? statusFuelInjection : null,
    rpm: keep('rpm') ? rpm : null,
    wheelKph: keep('wheel_kph') ? wheelKph : null,
    gear: keep('gear') ? gear : null,
    throttle: keep('throttle') ? throttle : null,
    leanDeg: keep('lean_deg') ? lean : null,
    accelG: keep('accel_g') ? accel : null,
    wheelieFlag: keep('wheelie_flag') ? wheelieFlag : null,
    wheelieAngle: keep('wheelie_angle') ? wheelieAngle : null,
    tcsLevelHb: keep('tcs_level_hb') ? tcsHb : null,
    tcsLevelLb: keep('tcs_level_lb') ? tcsLb : null,
    riderTorqueRequest: keep('rider_torque_request') ? riderTorque : null,
    engineTorqueRequest: keep('engine_torque_request') ? engineTorqueReq : null,
    engineTorqueActual: keep('engine_torque_actual') ? engineTorqueAct : null,
    absCplInspMode: absCpl,
    absSystemError: absErr,
    absFrontStatus: absFront,
    absRearStatus: absRear,
    frontBrakePressure: frontBrake,
    absTarget: absTarget,
    absIndicator: absIndicator,
    switchingInfo: switchingInfo,
  );
}
