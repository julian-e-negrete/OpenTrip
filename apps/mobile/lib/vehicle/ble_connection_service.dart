import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kawasaki_rideology_ble/kawasaki_rideology_ble.dart';

import 'kawasaki_connector.dart';

enum BleConnectionState { disconnected, scanning, connecting, connected, failed }

/// The single, shared Kawasaki BLE connection for the whole app.
///
/// Before this existed, the standalone Vehicle tab (since removed — BLE
/// connection is now a property of a vehicle, surfaced from its row on
/// vehicles/vehicle_list_screen.dart) and the Record tab's "Connect
/// bike" card (trip/recording_screen.dart) each ran their own
/// `KawasakiConnector.connect()` and held their own `KawasakiClient`.
/// Connecting on one and switching to the other triggered a second,
/// independent scan + GATT connect to the same physical bike — most BLE
/// peripherals (this one included) only accept one active GATT
/// connection, so the second attempt would fail outright or silently
/// disconnect the first. This singleton owns the one real connection;
/// every screen reads and drives it through here instead of owning its
/// own `KawasakiClient`, so "connect" from anywhere means the same
/// connection shows up everywhere.
class BleConnectionService {
  BleConnectionService._();
  static final instance = BleConnectionService._();

  final ValueNotifier<BleConnectionState> stateNotifier = ValueNotifier(BleConnectionState.disconnected);

  /// The latest telemetry snapshot, for screens that just want to display
  /// current numbers (both tabs use this for their live readout).
  final ValueNotifier<RidingTelemetry?> telemetryNotifier = ValueNotifier(null);

  String? lastError;

  KawasakiClient? _client;
  StreamSubscription<RidingTelemetry>? _telemetrySub;

  BleConnectionState get state => stateNotifier.value;
  bool get isConnected => state == BleConnectionState.connected;
  bool get isBusy => state == BleConnectionState.scanning || state == BleConnectionState.connecting;

  /// Every telemetry frame since connecting — for a consumer that needs
  /// each one, not just the latest snapshot (the trip recorder's max/min
  /// tracking). Null until connected. It's the underlying
  /// `KawasakiClient`'s own broadcast stream, so this is safe to listen
  /// to from more than one place at once alongside [telemetryNotifier].
  Stream<RidingTelemetry>? get telemetryStream => _client?.telemetry;

  Future<void> connect({void Function(String)? onLog}) async {
    if (isBusy || isConnected) return;
    stateNotifier.value = BleConnectionState.scanning;
    lastError = null;
    try {
      await KawasakiConnector.ensurePermissions();
      final result = await KawasakiConnector.findBike(onLog: onLog);
      if (result == null) {
        throw StateError('No Kawasaki-* bike found nearby. Make sure it\'s on and in range.');
      }
      stateNotifier.value = BleConnectionState.connecting;
      final client = await KawasakiConnector.connect(result: result, onLog: onLog);
      _client = client;
      _telemetrySub = client.telemetry.listen((t) => telemetryNotifier.value = t);
      stateNotifier.value = BleConnectionState.connected;
    } catch (e) {
      // StateError/Exception's toString() prefixes the message with
      // "Bad state: "/"Exception: " — meant for a stack trace, not a
      // banner a rider reads mid-ride. Strip it so only the actual
      // reason shows.
      lastError = e is StateError
          ? e.message
          : e.toString().replaceFirst(RegExp(r'^(Bad state|Exception): '), '');
      stateNotifier.value = BleConnectionState.failed;
    }
  }

  Future<void> disconnect() async {
    await _telemetrySub?.cancel();
    _telemetrySub = null;
    await _client?.dispose();
    _client = null;
    telemetryNotifier.value = null;
    stateNotifier.value = BleConnectionState.disconnected;
  }
}
