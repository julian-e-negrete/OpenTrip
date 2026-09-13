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

  // A real bike found in production (2026-09-09, via a signed-in user's
  // synced trip): the GATT link itself can stay nominally "connected"
  // (transport.connectionState never fires false, so _onLinkStateChanged
  // never runs) while the bike simply stops sending its live telemetry
  // frame (0x4A/ridingLogMid) for the rest of the ride — RSSI/vibration
  // dropout, a firmware hiccup, whatever the cause. Confirmed directly
  // from real trip data: one 27-minute ride had ble_speed_kph/ble_rpm
  // frozen at the exact same value for 212 of 234 points (the last 24
  // minutes straight) while GPS speed kept varying normally throughout —
  // the stale reading kept getting stamped onto every point because
  // isConnected stayed true the whole time. RidingTelemetry.timestamp is
  // set only when a real 0x4A frame is parsed (kawasaki_client.dart's
  // _handleNotify), so it's the right signal to watch: if it stops
  // advancing for this long while nominally connected, the link is dead
  // in every way that matters even though the OS hasn't said so yet —
  // treat it exactly like _onLinkStateChanged(false) would.
  static const _staleTelemetryTimeout = Duration(seconds: 15);
  Timer? _staleWatchdog;

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
        throw StateError('No Kawasaki bike found nearby. Make sure it\'s on and in range.');
      }
      stateNotifier.value = BleConnectionState.connecting;
      final client = await KawasakiConnector.connect(result: result, onLog: onLog);
      _client = client;
      _telemetrySub = client.telemetry.listen((t) => telemetryNotifier.value = t);
      _linkSub = client.connectionState.listen(_onLinkStateChanged);
      _reconnectAttempt = 0;
      stateNotifier.value = BleConnectionState.connected;
      unawaited(BleKeepAliveService.instance.start());
      _startStaleWatchdog();
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
    _stopStaleWatchdog();
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
    _stopStaleWatchdog();
    await _linkSub?.cancel();
    _linkSub = null;
    await _telemetrySub?.cancel();
    _telemetrySub = null;
    // The old client (and its transport's live characteristic-notification
    // subscriptions — see flutter_blue_plus_transport.dart's _notifySubs)
    // was previously just dropped here, not disposed: disconnect() is the
    // only other place that ever called _client.dispose(), and this path
    // isn't that. dispose() -> transport.disconnect() is safe to call on
    // an already-dropped link (guarded by isConnected there), so this is
    // a pure cleanup, not a behavior change to the reconnect flow itself.
    // On a bike that drops in and out of range repeatedly, never cleaning
    // this up meant every dropped connection left its old notification
    // listener alive and leaking for the rest of the ride.
    unawaited(_client?.dispose());
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
      _startStaleWatchdog();
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

  void _startStaleWatchdog() {
    _staleWatchdog?.cancel();
    _staleWatchdog = Timer.periodic(const Duration(seconds: 5), (_) => _checkTelemetryFreshness());
  }

  void _stopStaleWatchdog() {
    _staleWatchdog?.cancel();
    _staleWatchdog = null;
  }

  /// See the doc comment on [_staleTelemetryTimeout]: a live-but-silent
  /// bike is otherwise indistinguishable from a genuinely fine connection
  /// with nothing new to report, so this is the only thing that catches
  /// it. Deliberately does nothing until at least one real frame has ever
  /// arrived ([telemetryNotifier] stays null until then) — the scan +
  /// GATT connect + handshake before that can easily take longer than
  /// the timeout on its own, and that's not a stale *telemetry* frame,
  /// there's simply been no first frame yet.
  void _checkTelemetryFreshness() {
    if (state != BleConnectionState.connected) return;
    final telemetry = telemetryNotifier.value;
    if (telemetry == null) return;
    final silentFor = DateTime.now().difference(telemetry.timestamp);
    if (silentFor <= _staleTelemetryTimeout) return;
    logBuffer.add(
      'BLE: no live telemetry frame in ${silentFor.inSeconds}s while still nominally connected — '
      'treating as dropped and reconnecting',
    );
    unawaited(_handleUnexpectedDisconnect());
  }
}
