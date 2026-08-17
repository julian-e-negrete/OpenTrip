import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:kawasaki_rideology_ble/kawasaki_rideology_ble.dart';

import '../auth/current_user.dart';
import '../autostart/driving_detector_task.dart' show kStopAutoTripMessage;
import '../data/data_events.dart';
import '../data/models/trip.dart';
import '../data/models/trip_point.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/trip_repository.dart';
import '../data/repositories/vehicle_repository.dart';
import '../gamification/gamification_service.dart';
import '../vehicle/ble_connection_service.dart';
import 'location_recorder.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

/// How many points to buffer before writing them to SQLite as a batch —
/// keeps write volume sane on a long trip without losing much on a crash.
const _flushEvery = 20;

class _RecordingScreenState extends State<RecordingScreen> {
  final _recorder = LocationRecorder();
  final _pointBuffer = <TripPoint>[];

  List<Vehicle> _vehicles = [];
  Vehicle? _selectedVehicle;
  Trip? _activeTrip;
  RecordingStats? _stats;
  String? _error;
  bool _loadingVehicles = true;

  /// True when [_activeTrip] is one autostart/driving_detector_task.dart
  /// started, not this screen's own [_start] — that background isolate
  /// owns the real running LocationRecorder in that case, not this
  /// screen, so there's no live [_stats] to show and "Stop & save" has to
  /// send a message rather than call [_recorder] directly. See
  /// data/repositories/trip_repository.dart's activeTripFor doc comment.
  bool _autoManaged = false;

  StreamSubscription<TripPoint>? _pointSub;
  StreamSubscription<RecordingStats>? _statsSub;

  // Optional live vehicle telemetry over the connection shared with the
  // Vehicle tab (see vehicle/ble_connection_service.dart) — independent
  // of GPS recording, a bike connection can fail, never be attempted, or
  // already be connected from the other tab, and the trip is still saved
  // fine either way (GPS-only if so).
  final _ble = BleConnectionService.instance;

  // Trip-scoped subscription to every telemetry frame, for max/min
  // tracking below — separate from _ble.telemetryNotifier (just the
  // latest snapshot, for display), and only live while a trip is
  // actually recording, so idle time connected-but-not-recording doesn't
  // get folded into a trip's bike stats.
  StreamSubscription<RidingTelemetry>? _bleTelemetrySub;
  double? _bleMaxSpeedKph;
  int? _bleMaxRpm;
  double? _bleMaxLeanDeg;
  double? _bleMaxBrakeKpa;
  int? _bleMinWaterTemp;
  int? _bleMaxWaterTemp;

  late String _userId;

  bool get _vehicleSupportsBle => _selectedVehicle?.bleConnector == VehicleBleConnector.kawasakiRideology;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
    // This screen lives inside HomeShell's IndexedStack, so initState only
    // ever runs once — reload the vehicle list whenever one is
    // added/edited/deleted elsewhere (e.g. the Vehicles tab), instead of
    // staying stuck on whatever existed at the moment this tab first
    // mounted. See data/data_events.dart.
    DataEvents.instance.listenable.addListener(_loadVehicles);
    // The bike connection is shared with the Vehicle tab (see
    // vehicle/ble_connection_service.dart) — react to it changing from
    // over there too, not just from this screen's own Connect/Disconnect
    // buttons.
    _ble.stateNotifier.addListener(_onBleStateChanged);
    _ble.telemetryNotifier.addListener(_onBleTelemetryNotifierChanged);
  }

  @override
  void dispose() {
    DataEvents.instance.listenable.removeListener(_loadVehicles);
    _ble.stateNotifier.removeListener(_onBleStateChanged);
    _ble.telemetryNotifier.removeListener(_onBleTelemetryNotifierChanged);
    _pointSub?.cancel();
    _statsSub?.cancel();
    _bleTelemetrySub?.cancel();
    // Deliberately doesn't call _ble.disconnect() — this is a shared
    // connection (see vehicle/ble_connection_service.dart), so this
    // screen going away shouldn't drop it out from under the Vehicle tab.
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _loadVehicles() async {
    _userId = await CurrentUser.instance.id();
    final vehicles = await VehicleRepository.instance.listForUser(_userId);
    // Durable, database-backed check — catches a trip
    // autostart/driving_detector_task.dart started while this screen
    // wasn't watching (the app was closed, or just hadn't refreshed yet),
    // and equally catches one it just finished while this screen still
    // thought it was running.
    final active = await TripRepository.instance.activeTripFor(_userId);
    if (!mounted) return;
    setState(() {
      _vehicles = vehicles;
      // Keep the current selection if it still exists (e.g. a vehicle was
      // added elsewhere while this tab already had one picked, possibly
      // mid-recording) — only fall back to the first vehicle if it's gone
      // or nothing was selected yet.
      final selected = _selectedVehicle;
      final stillExists = selected != null && vehicles.any((v) => v.id == selected.id);
      if (!stillExists) {
        _selectedVehicle = vehicles.isEmpty ? null : vehicles.first;
      }

      if (_autoManaged) {
        if (active == null) {
          // Finished elsewhere — reconcile back to idle.
          _activeTrip = null;
          _autoManaged = false;
        } else {
          _activeTrip = active;
        }
      } else if (_activeTrip == null && active != null && active.autoStarted) {
        _activeTrip = active;
        _autoManaged = true;
        final vehicleMatch = vehicles.where((v) => v.id == active.vehicleId);
        if (vehicleMatch.isNotEmpty) _selectedVehicle = vehicleMatch.first;
      }

      _loadingVehicles = false;
    });
  }

  /// Starts (or joins) the trip-scoped accumulation subscription whenever
  /// the shared connection is up and a trip is actively recording, and
  /// tears it down the moment either stops being true — whether that
  /// change came from this screen's own buttons or from the Vehicle tab.
  void _onBleStateChanged() {
    final connected = _ble.isConnected;
    if (connected && _activeTrip != null && _bleTelemetrySub == null) {
      _bleTelemetrySub = _ble.telemetryStream!.listen(_onBleTelemetry);
    } else if (!connected && _bleTelemetrySub != null) {
      unawaited(_bleTelemetrySub!.cancel());
      _bleTelemetrySub = null;
    }
    if (mounted) setState(() {});
  }

  void _onBleTelemetryNotifierChanged() {
    if (mounted) setState(() {});
  }

  void _onBleTelemetry(RidingTelemetry t) {
    final speed = t.speedKph?.toDouble();
    if (speed != null && (_bleMaxSpeedKph == null || speed > _bleMaxSpeedKph!)) _bleMaxSpeedKph = speed;
    if (t.rpm != null && (_bleMaxRpm == null || t.rpm! > _bleMaxRpm!)) _bleMaxRpm = t.rpm;
    if (t.leanDeg != null) {
      final absLean = t.leanDeg!.abs();
      if (_bleMaxLeanDeg == null || absLean > _bleMaxLeanDeg!) _bleMaxLeanDeg = absLean;
    }
    if (t.frontBrakePressureKpa != null &&
        (_bleMaxBrakeKpa == null || t.frontBrakePressureKpa! > _bleMaxBrakeKpa!)) {
      _bleMaxBrakeKpa = t.frontBrakePressureKpa;
    }
    if (t.waterTemperatureC != null) {
      if (_bleMinWaterTemp == null || t.waterTemperatureC! < _bleMinWaterTemp!) {
        _bleMinWaterTemp = t.waterTemperatureC;
      }
      if (_bleMaxWaterTemp == null || t.waterTemperatureC! > _bleMaxWaterTemp!) {
        _bleMaxWaterTemp = t.waterTemperatureC;
      }
    }
  }

  Future<void> _start() async {
    final vehicle = _selectedVehicle;
    if (vehicle == null) return;

    // Rare race: autostart/driving_detector_task.dart started a trip in
    // the instant before this button was tapped. Adopt it instead of
    // starting a second, competing recording.
    final alreadyActive = await TripRepository.instance.activeTripFor(_userId);
    if (alreadyActive != null) {
      setState(() {
        _activeTrip = alreadyActive;
        _autoManaged = alreadyActive.autoStarted;
      });
      return;
    }

    setState(() => _error = null);
    try {
      final trip = await TripRepository.instance.startTrip(userId: _userId, vehicleId: vehicle.id);
      await _recorder.start(trip.id);

      _pointSub = _recorder.pointStream.listen((point) {
        _pointBuffer.add(point);
        if (_pointBuffer.length >= _flushEvery) _flushPoints();
      });
      _statsSub = _recorder.statsStream.listen((stats) {
        if (mounted) setState(() => _stats = stats);
      });

      // The bike may already be connected from earlier (this tab or the
      // Vehicle tab) — start folding its telemetry into this trip's
      // max/min stats right away rather than waiting for a state change.
      if (_ble.isConnected && _bleTelemetrySub == null) {
        _bleTelemetrySub = _ble.telemetryStream!.listen(_onBleTelemetry);
      }

      setState(() => _activeTrip = trip);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  /// Stops a trip autostart/driving_detector_task.dart owns — that
  /// background isolate holds the actual running LocationRecorder, not
  /// this screen, so stopping is a message, not a local call. The
  /// isolate finishes the trip, runs gamification, and reports back via
  /// AutoStartController's data callback, which pokes DataEvents and
  /// brings this screen back to idle through the normal _loadVehicles path.
  void _stopAutoManaged() {
    FlutterForegroundTask.sendDataToTask(kStopAutoTripMessage);
    setState(() {
      _activeTrip = null;
      _autoManaged = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Stopping — this trip will appear in Trips shortly.')));
  }

  Future<void> _flushPoints() async {
    if (_pointBuffer.isEmpty) return;
    final toFlush = List<TripPoint>.of(_pointBuffer);
    _pointBuffer.clear();
    await TripRepository.instance.appendPoints(toFlush);
  }

  Future<void> _stop() async {
    final trip = _activeTrip;
    if (trip == null) return;

    final finalStats = await _recorder.stop();
    await _pointSub?.cancel();
    await _statsSub?.cancel();
    await _bleTelemetrySub?.cancel();
    _bleTelemetrySub = null;
    await _flushPoints();

    final finished = trip.finish(
      endedAt: DateTime.now(),
      distanceMeters: finalStats.distanceMeters,
      durationSeconds: finalStats.elapsed.inSeconds,
      avgSpeedKph: finalStats.avgSpeedKph,
      maxSpeedKph: finalStats.maxSpeedKph,
      pointCount: finalStats.pointCount,
      bleMaxSpeedKph: _bleMaxSpeedKph,
      bleMaxRpm: _bleMaxRpm,
      bleMaxLeanDeg: _bleMaxLeanDeg,
      bleMaxBrakePressureKpa: _bleMaxBrakeKpa,
      bleMinWaterTemperatureC: _bleMinWaterTemp,
      bleMaxWaterTemperatureC: _bleMaxWaterTemp,
    );
    await TripRepository.instance.finishTrip(finished);
    // Deliberately doesn't disconnect the bike here — the connection is
    // shared with the Vehicle tab (vehicle/ble_connection_service.dart),
    // so ending this trip shouldn't drop it out from under that tab if
    // it's also being watched. Disconnecting is a user action (the
    // "Disconnect" button on either tab), not a trip-lifecycle side
    // effect.

    // Territory + trophies (gamification/gamification_service.dart) — best
    // done with this trip's own points before they're needed elsewhere, and
    // cheap even for a long trip since it's all local reads/writes.
    final points = await TripRepository.instance.pointsForTrip(finished.id);
    final newTrophies = await GamificationService.processFinishedTrip(
      userId: _userId,
      trip: finished,
      points: points,
    );

    if (!mounted) return;
    setState(() {
      _activeTrip = null;
      _stats = null;
      _bleMaxSpeedKph = null;
      _bleMaxRpm = null;
      _bleMaxLeanDeg = null;
      _bleMaxBrakeKpa = null;
      _bleMinWaterTemp = null;
      _bleMaxWaterTemp = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Trip saved: ${finished.distanceKm.toStringAsFixed(2)} km')),
    );
    for (final trophy in newTrophies) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          icon: Icon(trophy.icon, size: 40, color: Colors.amber),
          title: Text('Trophy earned: ${trophy.name}'),
          content: Text(trophy.description),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Nice')),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Record trip')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loadingVehicles
            ? const Center(child: CircularProgressIndicator())
            : _vehicles.isEmpty
            ? const Center(
                child: Text('Add a vehicle first (Vehicles tab) before recording a trip.'),
              )
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final recording = _activeTrip != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<Vehicle>(
          initialValue: _selectedVehicle,
          decoration: const InputDecoration(labelText: 'Vehicle', border: OutlineInputBorder()),
          items: _vehicles.map((v) => DropdownMenuItem(value: v, child: Text(v.name))).toList(),
          onChanged: recording
              ? null
              : (v) {
                  if (v?.id == _selectedVehicle?.id) return;
                  // A different vehicle means a different physical bike —
                  // the current connection (shared with the Vehicle tab)
                  // no longer corresponds to what's selected.
                  _ble.disconnect();
                  setState(() => _selectedVehicle = v);
                },
        ),
        if (_vehicleSupportsBle) ...[
          const SizedBox(height: 12),
          _BleConnectionCard(
            state: _ble.state,
            error: _ble.lastError,
            telemetry: _ble.telemetryNotifier.value,
            onConnect: () => _ble.connect(),
            onDisconnect: _ble.disconnect,
          ),
        ],
        const SizedBox(height: 24),
        if (recording)
          (_autoManaged ? _AutoManagedBanner(startedAt: _activeTrip!.startedAt) : _StatsView(stats: _stats))
        else
          const Spacer(),
        const SizedBox(height: 24),
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 12),
        ],
        FilledButton.icon(
          onPressed: recording ? (_autoManaged ? _stopAutoManaged : _stop) : _start,
          icon: Icon(recording ? Icons.stop_circle_outlined : Icons.play_circle_outline),
          label: Text(recording ? 'Stop & save' : 'Start recording'),
          style: recording ? FilledButton.styleFrom(backgroundColor: Colors.redAccent) : null,
        ),
        if (!recording) const Spacer(),
      ],
    );
  }
}

class _BleConnectionCard extends StatelessWidget {
  const _BleConnectionCard({
    required this.state,
    required this.error,
    required this.telemetry,
    required this.onConnect,
    required this.onDisconnect,
  });

  final BleConnectionState state;
  final String? error;
  final RidingTelemetry? telemetry;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              state == BleConnectionState.connected ? Icons.bluetooth_connected : Icons.bluetooth,
              color: state == BleConnectionState.connected ? Colors.lightBlueAccent : Colors.grey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_statusText(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (state == BleConnectionState.connected && telemetry != null)
                    Text(
                      '${telemetry!.rpm ?? '—'} rpm · gear ${telemetry!.gear ?? '—'}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  if (state == BleConnectionState.failed && error != null)
                    Text(error!, style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
                ],
              ),
            ),
            if (state == BleConnectionState.connected)
              TextButton(onPressed: onDisconnect, child: const Text('Disconnect'))
            else if (state == BleConnectionState.scanning || state == BleConnectionState.connecting)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            else
              TextButton(onPressed: onConnect, child: const Text('Connect')),
          ],
        ),
      ),
    );
  }

  String _statusText() => switch (state) {
    BleConnectionState.disconnected => 'Bike not connected (GPS only)',
    BleConnectionState.scanning => 'Scanning for bike…',
    BleConnectionState.connecting => 'Connecting to bike…',
    BleConnectionState.connected => 'Bike connected',
    BleConnectionState.failed => 'Bike connection failed',
  };
}

/// Shown instead of [_StatsView] while auto-detected driving is being
/// recorded by autostart/driving_detector_task.dart — no live distance
/// to show here (that stream lives in the background isolate), just
/// confirmation that it's happening.
class _AutoManagedBanner extends StatelessWidget {
  const _AutoManagedBanner({required this.startedAt});
  final DateTime startedAt;

  @override
  Widget build(BuildContext context) {
    final started = startedAt.toLocal().toString().substring(11, 16);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.directions_car_filled_outlined, size: 32, color: Colors.tealAccent),
            const SizedBox(height: 8),
            const Text('Recording automatically', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              'Auto-detected driving since $started — check the Trips tab once it\'s stopped.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsView extends StatelessWidget {
  const _StatsView({required this.stats});
  final RecordingStats? stats;

  String _fmtDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = stats;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              s == null ? '0.00' : (s.distanceMeters / 1000).toStringAsFixed(2),
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
            ),
            const Text('km'),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Stat(label: 'Time', value: s == null ? '--:--:--' : _fmtDuration(s.elapsed)),
                _Stat(
                  label: 'Speed',
                  value: s?.currentSpeedKph == null ? '—' : '${s!.currentSpeedKph!.toStringAsFixed(0)} km/h',
                ),
                _Stat(
                  label: 'Max',
                  value: s?.maxSpeedKph == null ? '—' : '${s!.maxSpeedKph!.toStringAsFixed(0)} km/h',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}
