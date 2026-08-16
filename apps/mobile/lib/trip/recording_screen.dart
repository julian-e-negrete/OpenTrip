import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../data/models/trip.dart';
import '../data/models/trip_point.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/trip_repository.dart';
import '../data/repositories/vehicle_repository.dart';
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

  StreamSubscription<TripPoint>? _pointSub;
  StreamSubscription<RecordingStats>? _statsSub;

  String get _userId => AuthService.instance.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  @override
  void dispose() {
    _pointSub?.cancel();
    _statsSub?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _loadVehicles() async {
    final vehicles = await VehicleRepository.instance.listForUser(_userId);
    if (!mounted) return;
    setState(() {
      _vehicles = vehicles;
      _selectedVehicle = vehicles.isEmpty ? null : vehicles.first;
      _loadingVehicles = false;
    });
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
    );
    await TripRepository.instance.finishTrip(finished);

    if (!mounted) return;
    setState(() {
      _activeTrip = null;
      _stats = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Trip saved: ${finished.distanceKm.toStringAsFixed(2)} km')),
    );
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
          items: _vehicles
              .map((v) => DropdownMenuItem(value: v, child: Text(v.name)))
              .toList(),
          onChanged: recording ? null : (v) => setState(() => _selectedVehicle = v),
        ),
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
