// Regression tests using real captured Rideology BLE5 frames, ported from
// tests/test_sample_frames.py in
// https://github.com/Zen3515/homeassistant-kawasaki-rideology-ble
// (Apache License 2.0). See /NOTICE.md at the repo root.
//
// Only fixtures for frames this package actually parses are ported (see
// README.md "What's implemented" for what's intentionally left out).
//
// If you're validating this protocol against a real 2026 Z500 ABS, capture
// your own frames per /docs/CAPTURE_GUIDE.md and add cases here — that's
// the fastest way to confirm or correct the field layout for your unit.

import 'package:kawasaki_rideology_ble/kawasaki_rideology_ble.dart';
import 'package:test/test.dart';

List<int> hx(String hex) {
  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return bytes;
}

const samples = <String, String>{
  '03': '03207a030002714d4c35455235303002724641444135353535027338ffffffffffffff',
  '08': '080c00ffff0a08017803e800c80064',
  '0B': '0b2000ffff0501486f6d654173736905027374616e7400000000000000000000000000',
  '1D': '1d0c801d00ffffffffffffffffffff',
  '20_a': '200c871b00050a00ffffffffffffff',
  '20_b': '200c9208000a08017803e800c80064',
  '20_c': '2020830b000501486f6d654173736905027374616e7400000000000000000000000000',
  '20_d': '202a8a4800050900ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
  '20_e': '202a8d1e01050c00ffffffffffffff050d00ffffffffffffff050e00ffffffffffffffffffffffffffffffffff',
  '20_f': '2002790300',
  '20_g': '20027b4000',
  '20_h': '20027d1a00',
  '20_i': '20027f1d00',
  '20_j': '2002814700',
  '20_k': '2002854100',
  '20_l': '2002934500',
  '20_m': '20029b4201',
  '30_a': '300c88ffff050a00ffffffffffffff',
  '30_b': '300c8bffff050900ffffffffffffff',
  '30_c': '300c8effff050c00ffffffffffffff',
  '30_d': '300c8fffff050d00ffffffffffffff',
  '30_e': '300c90ffff050e00ffffffffffffff',
  '30_f': '302084ffff0501486f6d654173736905027374616e74000000ffffffffffffffffffff',
  '40': '40207c40000511fc77d417ffffffffffffffffffffffffffffffffffffffffffffffff',
  '41': '41528641000514000000000000009effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
  '42': '420001',
  '42_b': '420c804200ffffffffffffffffffff',
  '45_a': '4534a4ffffffffffffffffffffffff05175000004c00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
  '45_b': '4534b4ffffffffffffffffffffffff05175000004c00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
  '45_c': '4534c4ffffffffffffffffffffffff05175000004c00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
  '45_d': '4534d4ffffffffffffffffffffffff05175000004c00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
  '45_e': '4534e4ffffffffffffffffffffffff05175000004c00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
};

void main() {
  group('parseModelInfo (0x03)', () {
    test('decodes VIN and model name', () {
      final info = parseModelInfo(hx(samples['03']!));
      expect(info.modelName, 'ML5ER500');
      expect(info.vin, 'ML5ER500FADA55558');
      expect(info.vinPart71, 'ML5ER500');
      expect(info.vinPart72, 'FADA5555');
      expect(info.vinPart73, '8');
    });
  });

  group('parseMeterIndicationInit (0x08)', () {
    test('decodes the default startup profile', () {
      final parsed = parseMeterIndicationInit(hx(samples['08']!));
      expect(parsed.blockId, 0x0A);
      expect(parsed.commandId, 0x08);
      expect(parsed.enabled, true);
      expect(parsed.param1, 120);
      expect(parsed.param2, 1000);
      expect(parsed.param3, 200);
      expect(parsed.param4, 100);
      expect(parsed.isDefaultProfile, true);
    });
  });

  group('parsePhoneModel (0x0B)', () {
    test('decodes text chunks', () {
      final (text, chunkIds) = parsePhoneModel(hx(samples['0B']!));
      expect(text, 'HomeAssistant');
      expect(chunkIds, '0x01,0x02');
    });
  });

  group('parseCommonServiceConfigFlags (0x1D)', () {
    test('decodes an "all unsupported" service config', () {
      final parsed = parseCommonServiceConfigFlags(hx(samples['1D']!));
      expect(parsed, isNotNull);
      expect(parsed!.configValid, true);
      expect(parsed.supportedCount, 0);
      expect(parsed.unsupportedCount, 18);
      expect(parsed.kawasakiServiceSupported, false);
      expect(parsed.riderSettingSupported, false);
      expect(parsed.oilChangeSupported, false);
    });
  });

  group('parseAck (0x20)', () {
    final expected = <String, (int, String)>{
      '20_a': (0x1B, 'accepted'),
      '20_b': (0x08, 'rejected_or_unsupported'),
      '20_c': (0x0B, 'error_0x48'),
      '20_d': (0x48, 'accepted'),
      '20_e': (0x1E, 'accepted'),
      '20_f': (0x03, 'accepted'),
      '20_g': (0x40, 'accepted'),
      '20_h': (0x1A, 'accepted'),
      '20_i': (0x1D, 'accepted'),
      '20_j': (0x47, 'accepted'),
      '20_k': (0x41, 'accepted'),
      '20_m': (0x42, 'rejected_or_unsupported'),
    };

    expected.forEach((key, value) {
      final (ackCommand, resultText) = value;
      test('$key -> cmd=0x${ackCommand.toRadixString(16)} $resultText', () {
        final parsed = parseAck(hx(samples[key]!));
        expect(parsed.ackCommand, ackCommand);
        expect(parsed.resultText, resultText);
      });
    });

    test('20_b carries meter-indication params', () {
      final parsed = parseAck(hx(samples['20_b']!));
      expect(parsed.meterIndicationBlockId, 0x0A);
      expect(parsed.meterIndicationCommandId, 0x08);
      expect(parsed.meterIndicationParam1, 120);
      expect(parsed.meterIndicationParam2, 1000);
      expect(parsed.meterIndicationParam3, 200);
      expect(parsed.meterIndicationParam4, 100);
    });

    test('20_c carries phone-model text', () {
      final parsed = parseAck(hx(samples['20_c']!));
      expect(parsed.phoneModelText, 'HomeAssistant');
      expect(parsed.phoneModelChunkIds, '0x01,0x02');
    });
  });

  group('parseStatusReport (0x30)', () {
    final expected = <String, int>{
      '30_a': 0x0A,
      '30_b': 0x09,
      '30_c': 0x0C,
      '30_d': 0x0D,
      '30_e': 0x0E,
    };
    expected.forEach((key, blockId) {
      test('$key -> block_result 0x${blockId.toRadixString(16)}', () {
        final parsed = parseStatusReport(hx(samples[key]!));
        expect(parsed.statusType, 'block_result');
        expect(parsed.blockId, blockId);
        expect(parsed.resultCode, 0x00);
        expect(parsed.resultText, 'accepted');
      });
    });

    test('30_f decodes text chunks', () {
      final parsed = parseStatusReport(hx(samples['30_f']!));
      expect(parsed.statusType, 'text_chunks');
      expect(parsed.text, 'HomeAssistant');
    });
  });

  group('parseInfoConfigFlags (0x40) + parseMcInfo (0x41) + parseRidingLogExt (0x45)', () {
    test('0x40 reports 8 supported / 28 unsupported fields', () {
      final frame40 = parseInfoConfigFlags(hx(samples['40']!));
      expect(frame40.configValid, true);
      expect(frame40.supportedFields.length, 8);
      expect(frame40.unsupportedFields.length, 28);
      expect(frame40.supportedFields, contains('ecu_battery12V'));
      expect(frame40.supportedFields, contains('inlet_air_temperature'));
    });

    test('0x41 decodes ECU battery voltage and nulls gated-off fields', () {
      final frame40 = parseInfoConfigFlags(hx(samples['40']!));
      final cfg = {
        'ecu_battery12V': true,
        'meter_battery12V': false,
        'odometer': false,
        'fuel_gauge': false,
      };
      final frame41 = parseMcInfo(
        hx(samples['41']!),
        infoConfigFlags: frame40.flags,
        supportedFields: cfg,
      );
      expect(frame41.ecuBattery12V, closeTo(12.34375, 1e-9));
      expect(frame41.meterBattery12V, isNull);
      expect(frame41.odometer, isNull);
    });

    test('0x45 decodes water/inlet temperature and nulls gated-off fields', () {
      final frame40 = parseInfoConfigFlags(hx(samples['40']!));
      final cfg = {
        'water_temperature': true,
        'inlet_air_temperature': true,
        'odometer': false,
        'tire_pressure_fr': false,
      };
      for (final key in ['45_a', '45_b', '45_c', '45_d', '45_e']) {
        final frame45 = parseRidingLogExt(
          hx(samples[key]!),
          infoConfigFlags: frame40.flags,
          supportedFields: cfg,
        );
        expect(frame45.waterTemperature, 40, reason: key);
        expect(frame45.inletAirTemperature, 36, reason: key);
        expect(frame45.odometer, isNull, reason: key);
        expect(frame45.tirePressureFr, isNull, reason: key);
      }
    });
  });

  group('parseEmcInfo (0x42)', () {
    test('short request-command form', () {
      final parsed = parseEmcInfo(hx(samples['42']!));
      expect(parsed.packetType, 'request_command');
    });

    test('service-indicator-config-like form (EV/HEV variant)', () {
      final parsed = parseEmcInfo(hx(samples['42_b']!));
      expect(parsed.packetType, 'service_indicator_config_like');
      expect(parsed.serviceConfigLike, isNotNull);
      expect(parsed.serviceConfigLike!.configValid, true);
      expect(parsed.serviceConfigLike!.kawasakiServiceSupported, false);
      expect(parsed.serviceConfigLike!.riderSettingSupported, false);
      expect(parsed.serviceConfigLike!.oilChangeSupported, false);
      expect(parsed.serviceConfigLike!.supportedCount, 0);
      expect(parsed.serviceConfigLike!.unsupportedCount, 18);
    });
  });

  group('z500Er500fConfig sanity', () {
    test('model name and startup frames match upstream capture', () {
      expect(z500Er500fConfig.model, 'Kawasaki-ER500F');
      expect(z500Er500fConfig.startupFrames, [
        0x03, 0x40, 0x1A, 0x1D, 0x47, 0x0B, 0x41, 0x1B, 0x48, 0x1E, 0x08, 0x45, 0x42,
      ]);
      expect(z500Er500fConfig.supportedFields['rpm'], true);
      expect(z500Er500fConfig.supportedFields['lean_deg'], false);
    });
  });
}
