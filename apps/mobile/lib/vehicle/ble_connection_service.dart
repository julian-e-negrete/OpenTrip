import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kawasaki_rideology_ble/kawasaki_rideology_ble.dart';

import '../logging/error_reporter.dart';
import '../logging/log_buffer.dart';
import 'ble_keepalive_service.dart';
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
  StreamSubscription<bool>? _linkSub;

  // How many times connect() has retried an *unexpected* drop in a row —
  // reset to 0 on every successful (re)connect. Nothing before this
  // existed watched for the bike going silent mid-ride (out of range,
  // its own firmware sleeping, Android tearing the link down) at all —
  // the UI just kept reading "Connected" forever with telemetry quietly
  // dead. See _onLinkStateChanged.
  static const _maxAutoReconnectAttempts = 3;
  int _reconnectAttempt = 0;

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
      _linkSub = client.connectionState.listen(_onLinkStateChanged);
      _reconnectAttempt = 0;
      stateNotifier.value = BleConnectionState.connected;
      unawaited(BleKeepAliveService.instance.start());
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
    // Unsubscribe from the link-state stream first — otherwise the GATT
    // disconnect this triggers would itself fire _onLinkStateChanged,
    // which would read as an *unexpected* drop and kick off an auto-
    // reconnect right after the user asked to disconnect.
    await _linkSub?.cancel();
    _linkSub = null;
    await _telemetrySub?.cancel();
    _telemetrySub = null;
    await _client?.dispose();
    _client = null;
    telemetryNotifier.value = null;
    _reconnectAttempt = 0;
    stateNotifier.value = BleConnectionState.disconnected;
    unawaited(BleKeepAliveService.instance.stop());
  }

  /// Fires on every link-state change once connected — only unexpected
  /// drops reach here, since [disconnect] cancels this subscription
  /// before tearing down the GATT connection itself.
  void _onLinkStateChanged(bool connected) {
    if (connected) return;
    unawaited(_handleUnexpectedDisconnect());
  }

  Future<void> _handleUnexpectedDisconnect() async {
    await _linkSub?.cancel();
    _linkSub = null;
    await _telemetrySub?.cancel();
    _telemetrySub = null;
    _client = null;
    telemetryNotifier.value = null;

    _reconnectAttempt++;
    logBuffer.add('BLE: connection lost, reconnecting (attempt $_reconnectAttempt/$_maxAutoReconnectAttempts)');
    stateNotifier.value = BleConnectionState.connecting;

    try {
      await KawasakiConnector.ensurePermissions();
      final result = await KawasakiConnector.findBike();
      if (result == null) {
        throw StateError('Bike went out of range and couldn\'t be found again.');
      }
      final client = await KawasakiConnector.connect(result: result);
      _client = client;
      _telemetrySub = client.telemetry.listen((t) => telemetryNotifier.value = t);
      _linkSub = client.connectionState.listen(_onLinkStateChanged);
      logBuffer.add('BLE: reconnected automatically');
      _reconnectAttempt = 0;
      stateNotifier.value = BleConnectionState.connected;
      // Already running from the original connect() — restarting here
      // would be a harmless no-op (start() is idempotent) if it somehow
      // ever weren't.
      unawaited(BleKeepAliveService.instance.start());
    } catch (e, st) {
      if (_reconnectAttempt >= _maxAutoReconnectAttempts) {
        logBuffer.add('BLE: auto-reconnect gave up after $_reconnectAttempt attempt(s) — $e');
        unawaited(ErrorReporter.report('BLE auto-reconnect gave up', e, st));
        lastError = 'Connection to the bike was lost and couldn\'t be re-established.';
        _reconnectAttempt = 0;
        stateNotifier.value = BleConnectionState.failed;
        unawaited(BleKeepAliveService.instance.stop());
        return;
      }
      // Give the bike a moment before trying again rather than hammering
      // a scan the instant a connect attempt fails.
      await Future<void>.delayed(const Duration(seconds: 3));
      unawaited(_handleUnexpectedDisconnect());
    }
  }
}
