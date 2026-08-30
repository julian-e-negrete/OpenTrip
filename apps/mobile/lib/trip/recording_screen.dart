import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:kawasaki_rideology_ble/kawasaki_rideology_ble.dart';

import '../auth/current_user.dart';
import '../data/data_events.dart';
import '../data/models/trip.dart';
import '../data/models/trip_music_event.dart';
import '../data/models/trip_point.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/trip_repository.dart';
import '../data/repositories/vehicle_repository.dart';
import '../gamification/gamification_service.dart';
import '../vehicle/ble_connection_service.dart';
import 'camera_alerts.dart';
import 'lean_angle_tracker.dart';
import 'location_recorder.dart';
import 'spotify_now_playing.dart';

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
  StreamSubscription<CameraAlert>? _cameraAlertSub;

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

  /// The bike's own odometer reading, last-write-wins (not a max/min —
  /// see data/models/trip.dart's field comment) from whichever telemetry
  /// frame most recently reported one.
  double? _bleOdometerKm;

  // Phone-accelerometer lean-angle tracking (trip/lean_angle_tracker.dart)
  // — opt-in (see the "Track lean angle" toggle below), since it only
  // means anything if the phone is actually mounted rigidly to the bike,
  // not handheld or in a pocket.
  bool _trackLean = false;
  LeanAngleTracker? _leanTracker;
  StreamSubscription<double>? _leanAngleSub;
  double? _currentLeanDeg;

  // Music logging (trip/spotify_now_playing.dart) — always on for every
  // recording, same posture as camera_alerts.dart/driving-behavior
  // stats, not opt-in like lean tracking: there's no way for this to
  // produce misleading data the way handheld lean tracking can, it just
  // silently does nothing unless the rider has Spotify installed with
  // its "Device Broadcast Status" setting on. Independent of vehicle
  // type — this is about the rider, not the bike.
  StreamSubscription<SpotifyTrackEvent>? _musicSub;
  final _musicBuffer = <TripMusicEvent>[];
  int _musicSeq = 0;
  SpotifyTrackEvent? _currentTrack;

  late String _userId;

  bool get _vehicleSupportsBle => _selectedVehicle?.bleConnector == VehicleBleConnector.kawasakiRideology;
  bool get _vehicleIsMotorcycle => _selectedVehicle?.type == VehicleType.motorcycle;

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
    _cameraAlertSub = _recorder.cameraAlertStream.listen(_onCameraAlert);
  }

  @override
  void dispose() {
    DataEvents.instance.listenable.removeListener(_loadVehicles);
    _ble.stateNotifier.removeListener(_onBleStateChanged);
    _ble.telemetryNotifier.removeListener(_onBleTelemetryNotifierChanged);
    _pointSub?.cancel();
    _statsSub?.cancel();
    _cameraAlertSub?.cancel();
    _bleTelemetrySub?.cancel();
    _leanAngleSub?.cancel();
    _leanTracker?.dispose();
    _musicSub?.cancel();
    // Deliberately doesn't call _ble.disconnect() — this is a shared
    // connection (see vehicle/ble_connection_service.dart), so this
    // screen going away shouldn't drop it out from under the Vehicle tab.
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

  void _onCameraAlert(CameraAlert alert) {
    if (!mounted) return;
    final label = alert.camera.type == CameraAlertType.redLightCamera ? 'Red light camera' : 'Speed camera';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('⚠ $label ahead — ${alert.distanceMeters.toStringAsFixed(0)}m'),
        // A safety warning stays universal orange regardless of theme —
        // it shouldn't read as "just the app's accent color."
        backgroundColor: Colors.orange.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
    if (t.odometerTenthKm != null) _bleOdometerKm = t.odometerTenthKm! / 10.0;
  }

  Future<void> _start() async {
    final vehicle = _selectedVehicle;
    if (vehicle == null) return;

    setState(() => _error = null);
    try {
      final trip = await TripRepository.instance.startTrip(userId: _userId, vehicleId: vehicle.id);
      await _recorder.start(trip.id);

      _pointSub = _recorder.pointStream.listen((point) {
        // Stamp whatever the bike's latest telemetry frame was onto this
        // GPS fix — sampled at GPS-fix cadence, not BLE frame rate, so
        // point storage doesn't balloon (see trip_point.dart's field
        // comment). LocationRecorder itself stays GPS-only on purpose;
        // this is the one place recording a trip and reading the shared
        // BLE connection actually meet.
        final telemetry = _ble.isConnected ? _ble.telemetryNotifier.value : null;
        final enriched = telemetry == null
            ? point
            : point.copyWith(
                bleSpeedKph: telemetry.speedKph?.toDouble(),
                bleRpm: telemetry.rpm,
                bleGear: telemetry.gear,
                bleThrottlePercent: telemetry.throttlePercent,
                bleLeanDeg: telemetry.leanDeg,
                bleWaterTemperatureC: telemetry.waterTemperatureC,
              );
        _pointBuffer.add(enriched);
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

      if (_trackLean && _vehicleIsMotorcycle) {
        final tracker = LeanAngleTracker();
        _leanTracker = tracker;
        await tracker.start();
        _leanAngleSub = tracker.angleStream.listen((angle) {
          if (mounted) setState(() => _currentLeanDeg = angle);
        });
      }

      if (Platform.isAndroid) {
        _musicSub = SpotifyNowPlaying.instance.trackChanges.listen((event) {
          _musicBuffer.add(
            TripMusicEvent(
              tripId: trip.id,
              seq: _musicSeq++,
              track: event.track,
              artist: event.artist,
              album: event.album,
              spotifyUri: event.spotifyUri,
              // Receive time, deliberately not event.timestamp (Spotify's
              // own self-reported send time) — see that field's doc
              // comment in spotify_now_playing.dart for why: the first
              // broadcast a freshly-registered receiver gets can be a
              // replay of whatever was already playing, timestamped from
              // whenever that track actually started, which reads as a
              // bogus multi-hour offset once shown relative to the
              // trip's real start time on trip_detail_screen.dart's
              // Soundtrack list.
              startedAt: DateTime.now(),
            ),
          );
          if (mounted) setState(() => _currentTrack = event);
        });
      }

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
    await _bleTelemetrySub?.cancel();
    _bleTelemetrySub = null;

    double? phoneLeanMaxDeg;
    final leanTracker = _leanTracker;
    if (leanTracker != null) {
      await leanTracker.stop();
      phoneLeanMaxDeg = leanTracker.maxAngleDeg;
      await _leanAngleSub?.cancel();
      _leanAngleSub = null;
      await leanTracker.dispose();
      _leanTracker = null;
    }

    await _musicSub?.cancel();
    _musicSub = null;
    if (_musicBuffer.isNotEmpty) {
      await TripRepository.instance.appendMusicEvents(_musicBuffer);
      _musicBuffer.clear();
    }
    _musicSeq = 0;

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
      bleOdometerKm: _bleOdometerKm,
      behaviorMaxAccelG: _recorder.behaviorMaxAccelG,
      behaviorMaxBrakeG: _recorder.behaviorMaxBrakeG,
      behaviorMaxCorneringG: _recorder.behaviorMaxCorneringG,
      behaviorHardAccelCount: _recorder.behaviorHardAccelCount,
      behaviorHardBrakeCount: _recorder.behaviorHardBrakeCount,
      behaviorHardCorneringCount: _recorder.behaviorHardCorneringCount,
      phoneLeanMaxDeg: phoneLeanMaxDeg,
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
      _bleOdometerKm = null;
      _currentLeanDeg = null;
      _currentTrack = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Trip saved: ${finished.distanceKm.toStringAsFixed(2)} km')),
    );
    for (final trophy in newTrophies) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          // Gold regardless of theme — see monthly_recap_screen.dart's
          // matching comment on its own trophy list.
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
        if (_vehicleIsMotorcycle && !recording) ...[
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Track lean angle'),
            subtitle: const Text(
              'Needs the phone mounted rigidly to the bike (handlebar/tank '
              'mount) — not handheld or in a pocket. Calibrates for a moment '
              'once you start, assuming the bike is upright.',
            ),
            value: _trackLean,
            onChanged: (v) => setState(() => _trackLean = v ?? false),
          ),
        ],
        const SizedBox(height: 24),
        if (recording) ...[
          _StatsView(stats: _stats, currentLeanDeg: _currentLeanDeg),
          if (Platform.isAndroid) ...[
            const SizedBox(height: 12),
            _NowPlayingCard(track: _currentTrack),
          ],
        ] else
          const Spacer(),
        const SizedBox(height: 24),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
        ],
        FilledButton.icon(
          onPressed: recording ? _stop : _start,
          icon: Icon(recording ? Icons.stop_circle_outlined : Icons.play_circle_outline),
          label: Text(recording ? 'Stop & save' : 'Start recording'),
          style: recording
              ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error)
              : null,
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
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              state == BleConnectionState.connected ? Icons.bluetooth_connected : Icons.bluetooth,
              color: state == BleConnectionState.connected ? scheme.secondary : scheme.onSurfaceVariant,
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
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  if (state == BleConnectionState.failed && error != null)
                    Text(error!, style: TextStyle(fontSize: 12, color: scheme.error)),
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

class _StatsView extends StatelessWidget {
  const _StatsView({required this.stats, this.currentLeanDeg});
  final RecordingStats? stats;
  final double? currentLeanDeg;

  String _fmtDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: s == null ? '0.00' : (s.distanceMeters / 1000).toStringAsFixed(2),
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                      color: scheme.secondary,
                    ),
                  ),
                  TextSpan(
                    text: ' km',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Stat(label: 'Time', value: s == null ? '--:--:--' : _fmtDuration(s.elapsed)),
                _Stat(
                  label: 'Speed',
                  value: s?.currentSpeedKph == null ? '—' : '${s!.currentSpeedKph!.toStringAsFixed(0)} km/h',
                  color: scheme.primary,
                ),
                _Stat(
                  label: 'Max',
                  value: s?.maxSpeedKph == null ? '—' : '${s!.maxSpeedKph!.toStringAsFixed(0)} km/h',
                  color: scheme.primary,
                ),
                if (currentLeanDeg != null)
                  _Stat(label: 'Lean', value: '${currentLeanDeg!.toStringAsFixed(0)}°', color: scheme.tertiary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A standalone card docked near the bottom of the Record screen (see
/// _buildContent), separate from _StatsView's own card, so live "what's
/// playing" reads as its own persistent thing rather than one more line
/// buried inside the trip stats. Shows a "listening" placeholder before
/// the first track arrives, rather than only appearing once one does —
/// otherwise there's no visible sign the feature is even active until a
/// track change happens to fire.
class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({required this.track});
  final SpotifyTrackEvent? track;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = track;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.music_note, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: t == null
                    ? [
                        const Text('Listening for music…', style: TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          'Play something on Spotify',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ]
                    : [
                        Text(
                          t.track,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (t.artist != null)
                          Text(
                            t.artist!,
                            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
              ),
            ),
            if (t != null) Icon(Icons.graphic_eq, color: scheme.primary, size: 20),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: color ?? scheme.onSurface),
        ),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
