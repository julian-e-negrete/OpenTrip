// Connection/startup orchestration ported from the KawiBle5Client class in
// custom_components/kawasaki/kawi_ble5_client.py in
// https://github.com/Zen3515/homeassistant-kawasaki-rideology-ble
// (Apache License 2.0). See /NOTICE.md at the repo root. Restructured for
// Dart/Flutter (stream-based, no Home-Assistant-specific plumbing) but the
// startup frame sequence and response-matching logic are kept
// behaviourally identical, since bikes are known to reject or stall on an
// unfamiliar handshake.

import 'dart:async';
import 'dart:typed_data';

import 'bike_config.dart';
import 'frame_builder.dart';
import 'parsers.dart';
import 'protocol_ids.dart';
import 'telemetry.dart';
import 'transport.dart';

/// Thrown when a startup frame gets no matching response within the
/// configured timeout/retry budget.
class KawasakiStartupTimeoutException implements Exception {
  final int frameId;
  final String expected;
  KawasakiStartupTimeoutException(this.frameId, this.expected);

  @override
  String toString() =>
      'Timed out waiting for $expected (frame 0x${frameId.toRadixString(16).padLeft(2, '0').toUpperCase()})';
}

class KawasakiClient {
  final BleTransport transport;
  final BikeConfig config;
  final String phoneModel;

  KawasakiClient({
    required this.transport,
    required this.config,
    this.phoneModel = 'OpenTrip',
  });

  final _telemetryController = StreamController<RidingTelemetry>.broadcast();
  final List<Uint8List> _pendingFrames = [];
  static const _maxPendingFrames = 256;

  StreamSubscription<Uint8List>? _notifySub;
  RidingTelemetry _current = RidingTelemetry.empty();
  Map<String, int> _liveInfoConfigFlags = {};

  /// Live telemetry snapshots. Updates whenever a relevant frame (0x4A,
  /// 0x41, 0x45, or 0x03) is parsed. Subscribe before or after
  /// [runStartupSequence] — it's a broadcast stream.
  Stream<RidingTelemetry> get telemetry => _telemetryController.stream;

  RidingTelemetry get current => _current;

  Future<void> connect() async {
    await transport.connect();
    await transport.discoverServices();
    _notifySub = transport.notifications.listen(_handleNotify);
  }

  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    await transport.disconnect();
  }

  /// Sends the model's startup frame sequence and waits for each to be
  /// acknowledged (unless the frame is in [BikeConfig.startupNoWaitFrames]
  /// or the model disables response requirements entirely). Mirrors what
  /// the official Rideology app does immediately after connecting — bikes
  /// have been observed to need this exact shape before they'll start
  /// streaming frame 0x4A telemetry.
  Future<void> runStartupSequence() async {
    for (final frameId in config.startupFrames) {
      final shouldWait = config.requireStartupResponses && !config.startupNoWaitFrames.contains(frameId);
      final maxAttempts = shouldWait ? 1 + config.startupRetries : 1;

      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        final startIndex = _pendingFrames.length;
        await _sendStartupFrame(frameId);

        if (!shouldWait) break;

        try {
          await _waitForStartupResponse(frameId, startIndex: startIndex);
          break;
        } on TimeoutException {
          if (attempt >= maxAttempts) {
            final (_, expected) = _startupResponseMatcher(frameId);
            throw KawasakiStartupTimeoutException(frameId, expected);
          }
          await Future<void>.delayed(config.startupRetryDelay);
        }
      }

      if (frameId != config.startupFrames.last) {
        await Future<void>.delayed(config.startupInterFrameDelay);
      }
    }
  }

  Future<void> _sendStartupFrame(int frameId) async {
    final Uint8List frame = switch (frameId) {
      KawiFrame.phoneModel => buildPhoneModelFrame(phoneModel),
      KawiFrame.meterIndicationInit => buildMeterIndicationInitFrame(),
      KawiFrame.serviceIndicator => buildServiceIndicatorFrame(),
      KawiFrame.vehicleSettings => buildVehicleSettingsFrame(),
      KawiFrame.generalSettings => buildGeneralSettingsRequestFrame(),
      KawiFrame.emcInfo => buildSimpleFrame(KawiFrame.emcInfo, tail: 0x01),
      _ => buildSimpleFrame(frameId),
    };
    await transport.writeControlCharacteristic(frame, withResponse: config.controlWriteWithResponse);
  }

  Future<Uint8List> _waitForStartupResponse(int commandId, {required int startIndex}) async {
    final (predicate, expected) = _startupResponseMatcher(commandId);
    final deadline = DateTime.now().add(config.startupWaitTimeout);
    var cursor = startIndex;
    while (true) {
      final pendingLen = _pendingFrames.length;
      for (var i = cursor; i < pendingLen; i++) {
        if (predicate(_pendingFrames[i])) {
          final frame = _pendingFrames[i];
          _pendingFrames.removeAt(i);
          return frame;
        }
      }
      cursor = pendingLen;

      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative || remaining == Duration.zero) {
        throw TimeoutException('No response for 0x${commandId.toRadixString(16)} ($expected)');
      }
      await Future<void>.delayed(
        remaining < const Duration(milliseconds: 50) ? remaining : const Duration(milliseconds: 50),
      );
    }
  }

  /// Mirrors `_startup_response_matcher` in the upstream Python client:
  /// some frames echo back as themselves, others only ever show up wrapped
  /// in a generic ACK (0x20) naming the original command in byte 3.
  (bool Function(List<int>), String) _startupResponseMatcher(int commandId) {
    const respondsAsSameFrame = {
      KawiFrame.modelInfo,
      KawiFrame.mcInfoConfig,
      KawiFrame.generalSettingCapability,
      KawiFrame.commonService,
      KawiFrame.vehicleSettingConfig,
      KawiFrame.mcInfo,
      KawiFrame.generalSettings,
      KawiFrame.vehicleSettings,
      KawiFrame.serviceIndicator,
    };

    if (respondsAsSameFrame.contains(commandId)) {
      return (
        (payload) =>
            (payload.isNotEmpty && payload[0] == commandId) ||
            (payload.length > 3 && payload[0] == KawiFrame.ack && payload[3] == commandId),
        'frame 0x${commandId.toRadixString(16)} or ACK cmd=0x${commandId.toRadixString(16)}',
      );
    }

    if (commandId == KawiFrame.meterIndicationInit) {
      return (
        (payload) => payload.length > 3 && payload[0] == KawiFrame.ack && (payload[3] == 0x08 || payload[3] == 0x13),
        'ACK 0x20 cmd in {0x08,0x13}',
      );
    }

    if (commandId == KawiFrame.ridingLogExt || commandId == KawiFrame.emcInfo) {
      return (
        (payload) => payload.length > 3 && payload[0] == KawiFrame.ack && payload[3] == commandId,
        'ACK 0x20 cmd=0x${commandId.toRadixString(16)}',
      );
    }

    if (commandId == KawiFrame.phoneModel) {
      return ((payload) => payload.isNotEmpty && payload[0] == KawiFrame.ack, 'ACK 0x20');
    }

    return (
      (payload) =>
          (payload.isNotEmpty && payload[0] == commandId) ||
          (payload.length > 3 && payload[0] == KawiFrame.ack && payload[3] == commandId),
      'frame 0x${commandId.toRadixString(16)} or ACK 0x20',
    );
  }

  void _handleNotify(Uint8List payload) {
    if (payload.isEmpty) return;

    _pendingFrames.add(payload);
    if (_pendingFrames.length > _maxPendingFrames) {
      _pendingFrames.removeRange(0, _pendingFrames.length - _maxPendingFrames);
    }

    final frameId = payload[0];
    var updated = false;

    switch (frameId) {
      case KawiFrame.modelInfo:
        final info = parseModelInfo(payload);
        _current = _current.copyWith(vin: info.vin, modelName: info.modelName);
        updated = true;
        break;

      case KawiFrame.mcInfoConfig:
        final flags = parseInfoConfigFlags(payload);
        if (flags.flags.isNotEmpty) _liveInfoConfigFlags = flags.flags;
        break;

      case KawiFrame.mcInfo:
        final info = parseMcInfo(
          payload,
          infoConfigFlags: _liveInfoConfigFlags.isNotEmpty ? _liveInfoConfigFlags : config.infoConfigFlags,
          supportedFields: config.supportedFields.isEmpty ? null : config.supportedFields,
        );
        _current = _current.copyWith(
          ecuBattery12V: info.ecuBattery12V,
          odometerTenthKm: info.odometer,
          tripAKm: info.tripA,
          tripBKm: info.tripB,
          fuelGauge: info.fuelGauge,
        );
        updated = true;
        break;

      case KawiFrame.ridingLogExt:
        final ext = parseRidingLogExt(
          payload,
          infoConfigFlags: _liveInfoConfigFlags.isNotEmpty ? _liveInfoConfigFlags : config.infoConfigFlags,
          supportedFields: config.supportedFields.isEmpty ? null : config.supportedFields,
        );
        _current = _current.copyWith(
          waterTemperatureC: ext.waterTemperature,
          inletAirTemperatureC: ext.inletAirTemperature,
          tirePressureFrKpa: ext.tirePressureFr,
          tirePressureRrKpa: ext.tirePressureRr,
        );
        updated = true;
        break;

      case KawiFrame.ridingLogMid:
        final mid = parseRidingLogMid(
          payload,
          rpmMode: config.rpmMode,
          wheelMode: config.wheelMode,
          supportedFields: config.supportedFields.isEmpty ? null : config.supportedFields,
        );
        _current = _current.copyWith(
          timestamp: DateTime.now(),
          rpm: mid.rpm,
          speedKph: mid.wheelKph,
          gear: mid.gear,
          throttlePercent: mid.throttle,
          leanDeg: mid.leanDeg,
          accelG: mid.accelG,
          frontBrakePressureKpa: mid.frontBrakePressure,
          tcsLevelHb: mid.tcsLevelHb,
          tcsLevelLb: mid.tcsLevelLb,
        );
        updated = true;
    }

    if (updated) _telemetryController.add(_current);
  }

  Future<void> dispose() async {
    await disconnect();
    await _telemetryController.close();
  }
}
