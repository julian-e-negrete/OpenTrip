import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kawasaki_rideology_ble/kawasaki_rideology_ble.dart';

import '../auth/current_user.dart';
import '../data/data_events.dart';
import '../data/models/trip.dart';
import '../data/models/trip_point.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/trip_repository.dart';
import '../data/repositories/vehicle_repository.dart';
import '../gamification/gamification_service.dart';
import '../vehicle/kawasaki_connector.dart';
import 'location_recorder.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

/// How many points to buffer before writing them to SQLite as a batch —
/// keeps write volume sane on a long trip without losing much on a crash.
const _flushEvery = 20;

enum _BleState { none, connecting, connected, failed }

class _RecordingScreenState extends State<RecordingScreen> {
  final _recorder = LocationRecorder();
  final _pointBuffer = <TripPoint>[];

  List<Vehicle> _vehicles = [];
  Vehicle? _selectedVehicle;
  Trip? _activeTrip;
  RecordingStats? _stats;
  String? _error;
  bool _loadingVehicles = true;

  StreamSubscription<TripPoint>? _pointSub;
  StreamSubscription<RecordingStats>? _statsSub;

  // Optional live vehicle telemetry (see vehicle/kawasaki_connector.dart).
  // Independent of GPS recording — a bike connection can fail or never be
  // attempted and the trip is still saved as GPS-only.
  _BleState _bleState = _BleState.none;
  String? _bleError;
  KawasakiClient? _bleClient;
  RidingTelemetry? _bleLatest;
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
  }

  @override
  void dispose() {
    DataEvents.instance.listenable.removeListener(_loadVehicles);
    _pointSub?.cancel();
    _statsSub?.cancel();
    _bleTelemetrySub?.cancel();
    _bleClient?.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _loadVehicles() async {
    _userId = await CurrentUser.instance.id();
    final vehicles = await VehicleRepository.instance.listForUser(_userId);
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
      _loadingVehicles = false;
    });
  }

  Future<void> _connectBike() async {
    setState(() {
      _bleState = _BleState.connecting;
      _bleError = null;
    });
    try {
      await KawasakiConnector.ensurePermissions();
      final result = await KawasakiConnector.findBike();
      if (result == null) {
        throw StateError('No Kawasaki-* bike found nearby.');
      }
      final client = await KawasakiConnector.connect(result: result);
      _bleTelemetrySub = client.telemetry.listen(_onBleTelemetry);
      setState(() {
        _bleClient = client;
        _bleState = _BleState.connected;
      });
    } catch (e) {
      setState(() {
        _bleState = _BleState.failed;
        _bleError = e.toString();
      });
    }
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
    if (mounted) setState(() => _bleLatest = t);
  }

  Future<void> _disconnectBike() async {
    await _bleTelemetrySub?.cancel();
    _bleTelemetrySub = null;
    await _bleClient?.dispose();
    _bleClient = null;
    if (mounted) setState(() => _bleState = _BleState.none);
  }

  Future<void> _start() async {
    final vehicle = _selectedVehicle;
    if (vehicle == null) return;

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

      setState(() => _activeTrip = trip);
    } catch (e) {
      setState(() => _error = e.toString());
    }
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
    await _disconnectBike();

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
      _bleLatest = null;
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
                  _disconnectBike();
                  setState(() => _selectedVehicle = v);
                },
        ),
        if (_vehicleSupportsBle) ...[
          const SizedBox(height: 12),
          _BleConnectionCard(
            state: _bleState,
            error: _bleError,
            telemetry: _bleLatest,
            onConnect: _connectBike,
            onDisconnect: _disconnectBike,
          ),
        ],
        const SizedBox(height: 24),
        if (recording) _StatsView(stats: _stats) else const Spacer(),
        const SizedBox(height: 24),
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 12),
        ],
        FilledButton.icon(
          onPressed: recording ? _stop : _start,
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

  final _BleState state;
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
              state == _BleState.connected ? Icons.bluetooth_connected : Icons.bluetooth,
              color: state == _BleState.connected ? Colors.lightBlueAccent : Colors.grey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_statusText(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (state == _BleState.connected && telemetry != null)
                    Text(
                      '${telemetry!.rpm ?? '—'} rpm · gear ${telemetry!.gear ?? '—'}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  if (state == _BleState.failed && error != null)
                    Text(error!, style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
                ],
              ),
            ),
            if (state == _BleState.connected)
              TextButton(onPressed: onDisconnect, child: const Text('Disconnect'))
            else if (state == _BleState.connecting)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            else
              TextButton(onPressed: onConnect, child: const Text('Connect')),
          ],
        ),
      ),
    );
  }

  String _statusText() => switch (state) {
    _BleState.none => 'Bike not connected (GPS only)',
    _BleState.connecting => 'Connecting to bike…',
    _BleState.connected => 'Bike connected',
    _BleState.failed => 'Bike connection failed',
  };
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
