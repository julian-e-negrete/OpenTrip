import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kawasaki_rideology_ble/kawasaki_rideology_ble.dart';
import 'package:latlong2/latlong.dart';

import '../auth/current_user.dart';
import '../data/data_events.dart';
import '../data/models/trip.dart';
import '../data/models/trip_music_event.dart';
import '../data/models/trip_point.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/trip_repository.dart';
import '../data/repositories/vehicle_repository.dart';
import '../gamification/gamification_service.dart';
import '../theme/app_theme.dart';
import '../theme/dark_tile_layer.dart';
import '../theme/layout_prefs.dart';
import '../theme/ph_icons.dart';
import '../theme/primitives.dart';
import '../vehicle/ble_connection_service.dart';
import 'camera_alerts.dart';
import 'lean_angle_tracker.dart';
import 'location_recorder.dart';
import 'recording_controller.dart';
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

  /// Every point of the trip in progress, kept for the Record screen's
  /// live map (design handoff §3, variant A) — unlike [_pointBuffer],
  /// which is flushed to storage and cleared as it goes, this holds the
  /// whole route so far so the travelled polyline can be redrawn.
  final List<TripPoint> _liveRoutePoints = [];

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
    RecordingController.instance
      ..onRequestStart = _start
      ..onRequestStop = _stop;
    // HomeShell keeps this screen mounted (Offstage) for as long as the
    // app runs rather than rebuilding it each time the rider opens
    // Record, so initState only ever runs once — reload the vehicle list
    // whenever one is added/edited/deleted elsewhere (e.g. the Garage
    // tab), instead of staying stuck on whatever existed at first mount.
    // See data/data_events.dart.
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
    RecordingController.instance
      ..onRequestStart = null
      ..onRequestStop = null;
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
        _liveRoutePoints.add(enriched);
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
      RecordingController.instance.isRecording.value = true;
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

    RecordingController.instance.isRecording.value = false;
    if (!mounted) return;
    setState(() {
      _activeTrip = null;
      _liveRoutePoints.clear();
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
        builder: (dialogContext) => AlertDialog(
          // Gold regardless of theme — see monthly_recap_screen.dart's
          // matching comment on its own trophy list.
          icon: Icon(trophy.icon, size: 40, color: Colors.amber),
          title: Text('Trophy earned: ${trophy.name}'),
          content: Text(trophy.description),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Nice')),
          ],
        ),
      );
    }
  }

  Future<void> _pickVehicle() async {
    final chosen = await showModalBottomSheet<Vehicle>(
      context: context,
      backgroundColor: Noct.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Noct.rLg))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Container(
              width: 34,
              height: 3,
              decoration: BoxDecoration(color: Noct.n700, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 10),
            for (final v in _vehicles)
              ListTile(
                leading: Icon(v.type == VehicleType.car ? Ph.car : Ph.motorcycle, color: Noct.accent),
                title: Text(v.name, style: const TextStyle(color: Noct.text)),
                subtitle: Text(v.type.name, style: const TextStyle(color: Noct.n500)),
                trailing: v.id == _selectedVehicle?.id ? const Icon(Ph.caretRight, color: Noct.accent, size: 16) : null,
                onTap: () => Navigator.pop(context, v),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null || chosen.id == _selectedVehicle?.id) return;
    // A different vehicle means a different physical bike — the current
    // connection (shared with the Garage tab) no longer corresponds to
    // what's selected.
    _ble.disconnect();
    setState(() => _selectedVehicle = chosen);
  }

  Future<void> _showRecordSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Noct.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Noct.rLg))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Recording settings',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Noct.text),
              ),
              const SizedBox(height: 8),
              StatefulBuilder(
                builder: (context, setSheetState) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Track lean angle', style: TextStyle(color: Noct.text, fontSize: 13.5)),
                  subtitle: const Text(
                    'Needs the phone mounted rigidly to the bike — not handheld or in a pocket.',
                    style: TextStyle(color: Noct.n500, fontSize: 11),
                  ),
                  value: _trackLean,
                  onChanged: _activeTrip != null
                      ? null
                      : (v) => setSheetState(() => setState(() => _trackLean = v)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LayoutPrefs.instance,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Noct.bg,
          body: SafeArea(
            child: _loadingVehicles
                ? const Center(child: CircularProgressIndicator())
                : _vehicles.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Add a vehicle first (Garage tab) before recording a trip.',
                        style: TextStyle(color: Noct.n500, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _buildContent(),
          ),
        );
      },
    );
  }

  Widget _buildContent() {
    final recording = _activeTrip != null;
    final telemetry = _vehicleSupportsBle && _ble.state == BleConnectionState.connected
        ? _ble.telemetryNotifier.value
        : null;
    final leanNowDeg = _currentLeanDeg ?? telemetry?.leanDeg;
    final leanMaxDeg = _bleMaxLeanDeg ?? _leanTracker?.maxAngleDeg;
    final gpsLocked = !recording || (_stats?.pointCount ?? 0) > 0;

    var variant = LayoutPrefs.instance.record;
    if (variant == RecordVariant.cluster && telemetry == null) variant = RecordVariant.numbers;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: _RecordHeader(
            vehicle: _selectedVehicle,
            recording: recording,
            gpsLocked: gpsLocked,
            vehicleSupportsBle: _vehicleSupportsBle,
            bleState: _ble.state,
            onVehicleTap: recording ? null : _pickVehicle,
            onSettingsTap: _showRecordSettings,
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
            ),
          ),
        Expanded(
          child: switch (variant) {
            RecordVariant.map => _MapVariant(
              points: _liveRoutePoints,
              stats: _stats,
              track: _currentTrack,
              showMusic: Platform.isAndroid,
              currentLeanDeg: leanNowDeg,
              cameras: _recorder.camerasNotifier,
              onIdleLocation: _recorder.loadCamerasNear,
            ),
            RecordVariant.numbers => _NumbersVariant(
              stats: _stats,
              telemetry: telemetry,
              leanNowDeg: leanNowDeg,
              leanMaxDeg: leanMaxDeg,
            ),
            RecordVariant.cluster => _ClusterVariant(
              stats: _stats,
              telemetry: telemetry,
              leanDeg: leanNowDeg,
            ),
          },
        ),
        // The raised control on the tab bar can also start/stop a trip
        // (see home_shell.dart's onTapRecord), but nothing about it reads
        // as a record button on first glance, and a rider with no
        // vehicle-detail context has no other way to tell that tapping it
        // again — rather than a second navigation — is what starts the
        // trip. This is the reliable, unambiguous fallback for that.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: recording ? _stop : (_selectedVehicle == null ? null : _start),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: recording ? Theme.of(context).colorScheme.error : Noct.accent, width: 1.5),
                foregroundColor: recording ? Theme.of(context).colorScheme.error : Noct.a200,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              child: Text(recording ? 'Stop & save' : 'Start recording'),
            ),
          ),
        ),
      ],
    );
  }
}

String _fmtElapsed(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  return h > 0 ? '$h:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}' : '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
}

/// Shared by all three Record treatments: the vehicle pill, the BLE
/// status pill (only shown when it has something to say — connected,
/// or one of the mid-ride states from "States to build"), and the
/// settings glyph. Design handoff §3.
class _RecordHeader extends StatelessWidget {
  const _RecordHeader({
    required this.vehicle,
    required this.recording,
    required this.gpsLocked,
    required this.vehicleSupportsBle,
    required this.bleState,
    required this.onVehicleTap,
    required this.onSettingsTap,
  });

  final Vehicle? vehicle;
  final bool recording;
  final bool gpsLocked;
  final bool vehicleSupportsBle;
  final BleConnectionState bleState;
  final VoidCallback? onVehicleTap;
  final VoidCallback? onSettingsTap;

  Widget? _blePill() {
    if (recording && !gpsLocked) {
      return const _Pill(fill: Noct.n900, dot: Noct.n600, text: 'Searching for GPS', textColor: Noct.n500);
    }
    if (vehicleSupportsBle && bleState == BleConnectionState.connected) {
      return const _Pill(fill: Noct.a900, dot: Noct.a400, text: 'BLE live', textColor: Noct.a200);
    }
    if (recording && vehicleSupportsBle) {
      return const _Pill(fill: Noct.n900, dot: Noct.n600, text: 'Bike disconnected', textColor: Noct.n400);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onVehicleTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: Noct.surface,
              borderRadius: BorderRadius.circular(Noct.rMd),
              border: Border.all(color: Noct.n800),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(vehicle?.type == VehicleType.car ? Ph.car : Ph.motorcycle, size: 15, color: Noct.accent),
                const SizedBox(width: 6),
                Text(vehicle?.name ?? 'Select vehicle', style: const TextStyle(fontSize: 12.5, color: Noct.text)),
              ],
            ),
          ),
        ),
        Builder(
          builder: (context) {
            final pill = _blePill();
            if (pill == null) return const SizedBox.shrink();
            return Padding(padding: const EdgeInsets.only(left: 8), child: pill);
          },
        ),
        const Spacer(),
        GestureDetector(
          onTap: onSettingsTap,
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Ph.gearSix, size: 18, color: Noct.n500),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.fill, required this.dot, required this.text, required this.textColor});
  final Color fill;
  final Color dot;
  final Color textColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 11.5, color: textColor, fontWeight: FontWeight.w400)),
        ],
      ),
    );
  }
}

/// A `surface` row of equal cells separated by 1px `n800` gaps — the
/// Time/km-h/Lean strip shared by variants A and C.
class _ThreeCellStrip extends StatelessWidget {
  const _ThreeCellStrip({required this.cells});
  final List<(String label, String value, Color? color)> cells;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Noct.rMd),
      child: ColoredBox(
        color: Noct.n800,
        child: Row(
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0) const SizedBox(width: 1),
              Expanded(
                child: ColoredBox(
                  color: Noct.surface,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          cells[i].$2,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: cells[i].$3 ?? Noct.text,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          cells[i].$1.toUpperCase(),
                          style: const TextStyle(fontSize: 9.5, letterSpacing: 1.0, color: Noct.n500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NowPlayingRow extends StatelessWidget {
  const _NowPlayingRow({required this.track});
  final SpotifyTrackEvent? track;

  @override
  Widget build(BuildContext context) {
    final t = track;
    return NoctPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          const Icon(Ph.musicNoteFill, size: 16, color: Noct.a400),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: t == null
                  ? const [Text('Listening for music…', style: TextStyle(fontSize: 12.5, color: Noct.n400))]
                  : [
                      Text(
                        t.track,
                        style: const TextStyle(fontSize: 12.5, color: Noct.text),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (t.artist != null)
                        Text(
                          t.artist!,
                          style: const TextStyle(fontSize: 10.5, color: Noct.n500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Variant A — map first: "where am I, how far so far." Design handoff
/// §3. Full-bleed live map behind everything, following the rider as
/// new GPS fixes arrive.
class _MapVariant extends StatefulWidget {
  const _MapVariant({
    required this.points,
    required this.stats,
    required this.track,
    required this.showMusic,
    required this.currentLeanDeg,
    required this.cameras,
    required this.onIdleLocation,
  });

  final List<TripPoint> points;
  final RecordingStats? stats;
  final SpotifyTrackEvent? track;
  final bool showMusic;
  final double? currentLeanDeg;
  final ValueListenable<List<CameraPoint>> cameras;

  /// Called once an idle (pre-recording) GPS fix is available, so cameras
  /// can be loaded and shown on the map before a trip actually starts.
  final ValueChanged<Position> onIdleLocation;

  @override
  State<_MapVariant> createState() => _MapVariantState();
}

class _MapVariantState extends State<_MapVariant> {
  final _mapController = MapController();
  int _lastCenteredCount = 0;

  // Before a trip has produced any points of its own, this is what
  // "map first" actually shows — the rider's current position, so the
  // screen reads as ready-to-go rather than a blank box. Fetched once on
  // first mount; silently stays null (map stays blank, same as before
  // this fix) if there's no location permission/fix yet.
  LatLng? _idleLocation;

  @override
  void initState() {
    super.initState();
    _loadIdleLocation();
  }

  Future<void> _loadIdleLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;

      final last = await Geolocator.getLastKnownPosition();
      final pos = last ?? await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _idleLocation = LatLng(pos.latitude, pos.longitude));
      widget.onIdleLocation(pos);
    } catch (_) {
      // Location services off, or no fix yet — the map just stays blank
      // until a trip actually starts producing points.
    }
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
    final current = pts.isNotEmpty ? LatLng(pts.last.latitude, pts.last.longitude) : _idleLocation;

    if (current != null && pts.length != _lastCenteredCount) {
      _lastCenteredCount = pts.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(current, 16);
      });
    }

    final distanceKm = widget.stats == null ? 0.0 : widget.stats!.distanceMeters / 1000;

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Noct.canvas,
          child: current == null
              ? const SizedBox.shrink()
              : FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(initialCenter: current, initialZoom: 16),
                  children: [
                    const DarkTileLayer(),
                    if (pts.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: [for (final p in pts) LatLng(p.latitude, p.longitude)],
                            strokeWidth: 14,
                            color: Noct.accent.withValues(alpha: 0.16),
                          ),
                          Polyline(
                            points: [for (final p in pts) LatLng(p.latitude, p.longitude)],
                            strokeWidth: 3.5,
                            color: Noct.accent,
                            strokeCap: StrokeCap.round,
                          ),
                        ],
                      ),
                    ValueListenableBuilder<List<CameraPoint>>(
                      valueListenable: widget.cameras,
                      builder: (context, cameras, _) => MarkerLayer(
                        markers: [
                          for (final camera in cameras)
                            Marker(
                              point: LatLng(camera.latitude, camera.longitude),
                              width: 22,
                              height: 22,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.orange.shade800,
                                  border: Border.all(color: Noct.canvas, width: 1.5),
                                ),
                                child: Icon(
                                  camera.type == CameraAlertType.redLightCamera ? Ph.trafficSignal : Ph.securityCamera,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: current,
                          width: 17,
                          height: 17,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Noct.a400.withValues(alpha: 0.6), width: 1.5),
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 9,
                                height: 9,
                                child: DecoratedBox(decoration: BoxDecoration(color: Noct.a200, shape: BoxShape.circle)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Noct.bg.withValues(alpha: 0.85),
                  Colors.transparent,
                  Colors.transparent,
                  Noct.bg.withValues(alpha: 0.95),
                ],
                stops: const [0.0, 0.22, 0.42, 0.78],
              ),
            ),
          ),
        ),
        Positioned(
          left: 14,
          right: 14,
          bottom: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: distanceKm.toStringAsFixed(2), style: Noct.stat(64)),
                      const TextSpan(
                        text: ' km',
                        style: TextStyle(fontSize: 15, color: Noct.n400, fontWeight: FontWeight.w400),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _ThreeCellStrip(
                cells: [
                  ('Time', widget.stats == null ? '0:00' : _fmtElapsed(widget.stats!.elapsed), null),
                  (
                    'km/h',
                    widget.stats?.currentSpeedKph == null ? '0' : widget.stats!.currentSpeedKph!.toStringAsFixed(0),
                    null,
                  ),
                  (
                    'Lean',
                    widget.currentLeanDeg == null ? '—' : '${widget.currentLeanDeg!.toStringAsFixed(0)}°',
                    null,
                  ),
                ],
              ),
              if (widget.showMusic) ...[
                const SizedBox(height: 8),
                _NowPlayingRow(track: widget.track),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Variant B — numbers first: glanceable at a stop, works for cars.
/// Design handoff §3.
class _NumbersVariant extends StatelessWidget {
  const _NumbersVariant({required this.stats, required this.telemetry, required this.leanNowDeg, required this.leanMaxDeg});

  final RecordingStats? stats;
  final RidingTelemetry? telemetry;
  final double? leanNowDeg;
  final double? leanMaxDeg;

  @override
  Widget build(BuildContext context) {
    final distanceKm = stats == null ? 0.0 : stats!.distanceMeters / 1000;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DISTANCE',
            style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: Noct.n500, fontWeight: FontWeight.w400),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: distanceKm.toStringAsFixed(2), style: Noct.stat(92)),
                const TextSpan(text: ' km', style: TextStyle(fontSize: 18, color: Noct.n400, fontWeight: FontWeight.w400)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const FadingRule(),
          _Grid2x2(
            cells: [
              ('Elapsed', stats == null ? '0:00' : _fmtElapsed(stats!.elapsed), null),
              ('km/h now', stats?.currentSpeedKph == null ? '0' : stats!.currentSpeedKph!.toStringAsFixed(0), Noct.a300),
              ('km/h max', stats?.maxSpeedKph == null ? '0' : stats!.maxSpeedKph!.toStringAsFixed(0), null),
              ('Lean max', leanMaxDeg == null ? '—' : '${leanMaxDeg!.toStringAsFixed(0)}°', null),
            ],
          ),
          const SizedBox(height: 14),
          const FadingRule(),
          const SizedBox(height: 16),
          if (telemetry != null) _FromTheBike(telemetry: telemetry!),
        ],
      ),
    );
  }
}

class _Grid2x2 extends StatelessWidget {
  const _Grid2x2({required this.cells});
  final List<(String label, String value, Color? color)> cells;

  @override
  Widget build(BuildContext context) {
    Widget cell(int i) => Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            cells[i].$2,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.6,
              color: cells[i].$3 ?? Noct.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(cells[i].$1.toUpperCase(), style: const TextStyle(fontSize: 10, letterSpacing: 1.2, color: Noct.n500)),
        ],
      ),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Noct.n800))),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: const BoxDecoration(border: Border(right: BorderSide(color: Noct.n800))),
                  child: cell(0),
                ),
              ),
              Expanded(child: cell(1)),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: Noct.n800), top: BorderSide(color: Noct.n800)),
                  ),
                  child: cell(2),
                ),
              ),
              Expanded(
                child: DecoratedBox(
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Noct.n800))),
                  child: cell(3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FromTheBike extends StatelessWidget {
  const _FromTheBike({required this.telemetry});
  final RidingTelemetry telemetry;

  @override
  Widget build(BuildContext context) {
    final rpm = telemetry.rpm ?? 0;
    const redline = 11000;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'FROM THE BIKE',
              style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: Noct.n500, fontWeight: FontWeight.w400),
            ),
            Text(
              'gear ${telemetry.gear ?? '—'} · $rpm rpm',
              style: const TextStyle(fontSize: 11.5, color: Noct.a300, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: ColoredBox(
              color: Noct.n900,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (rpm / redline).clamp(0.0, 1.0),
                child: const DecoratedBox(
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [Noct.a700, Noct.accent])),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('0', style: TextStyle(fontSize: 10, color: Noct.n600)),
            Text('redline 11 000', style: TextStyle(fontSize: 10, color: Noct.n600)),
          ],
        ),
      ],
    );
  }
}

/// Variant C — cluster: bike-first, only earns its place over BLE.
/// Design handoff §3. Falls back to [_NumbersVariant] when the selected
/// vehicle has no live telemetry (handled by the caller).
class _ClusterVariant extends StatelessWidget {
  const _ClusterVariant({required this.stats, required this.telemetry, required this.leanDeg});

  final RecordingStats? stats;
  final RidingTelemetry? telemetry;
  final double? leanDeg;

  @override
  Widget build(BuildContext context) {
    final speed = telemetry?.speedKph?.toDouble() ?? stats?.currentSpeedKph ?? 0.0;
    final rpm = telemetry?.rpm ?? 0;
    final lean = leanDeg ?? 0.0;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      child: Column(
        children: [
          SizedBox(
            width: 300,
            height: 300,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(300, 300),
                  painter: _DialPainter(
                    speedFraction: (speed / 180).clamp(0.0, 1.0),
                    rpmFraction: (rpm / 11000).clamp(0.0, 1.0),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(speed.toStringAsFixed(0), style: Noct.stat(76)),
                    const SizedBox(height: 2),
                    const Text(
                      'KM/H',
                      style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: Noct.n500, fontWeight: FontWeight.w400),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(color: Noct.a900, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        'gear ${telemetry?.gear ?? '—'} · $rpm rpm',
                        style: const TextStyle(fontSize: 12, color: Noct.a200, fontWeight: FontWeight.w400),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _LeanBar(leanDeg: lean),
          const SizedBox(height: 14),
          _ThreeCellStrip(
            cells: [
              ('km', stats == null ? '0.00' : (stats!.distanceMeters / 1000).toStringAsFixed(2), null),
              ('Time', stats == null ? '0:00' : _fmtElapsed(stats!.elapsed), null),
              ('Water', telemetry?.waterTemperatureC == null ? '—' : '${telemetry!.waterTemperatureC}°', null),
            ],
          ),
        ],
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({required this.speedFraction, required this.rpmFraction});
  final double speedFraction;
  final double rpmFraction;

  static const _startAngle = 135 * math.pi / 180;
  static const _sweepFull = 270 * math.pi / 180;

  void _arc(Canvas canvas, Offset center, double radius, double strokeWidth, Color track, Color value, double fraction) {
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      _sweepFull,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
    // The value arc is only drawn once it has real length — a
    // round-capped stroke at zero length paints as a stray dot, which
    // reads as a bug rather than "zero."
    if (fraction > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        _startAngle,
        _sweepFull * fraction,
        false,
        Paint()
          ..color = value
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    _arc(canvas, center, 126, 16, Noct.n900, Noct.accent, speedFraction);
    _arc(canvas, center, 105, 4, Noct.n900, Noct.a400, rpmFraction);
  }

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) =>
      oldDelegate.speedFraction != speedFraction || oldDelegate.rpmFraction != rpmFraction;
}

class _LeanBar extends StatelessWidget {
  const _LeanBar({required this.leanDeg});
  final double leanDeg;

  @override
  Widget build(BuildContext context) {
    final dir = leanDeg == 0 ? '' : (leanDeg > 0 ? ' right' : ' left');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'LEAN',
              style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: Noct.n500, fontWeight: FontWeight.w400),
            ),
            Text(
              '${leanDeg.abs().toStringAsFixed(0)}°$dir',
              style: const TextStyle(fontSize: 12, color: Noct.a300, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 16,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final halfWidth = constraints.maxWidth / 2;
              final fillWidth = (leanDeg.abs() / 55).clamp(0.0, 1.0) * halfWidth;
              return Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: const SizedBox(height: 8, width: double.infinity, child: ColoredBox(color: Noct.n900)),
                  ),
                  Container(width: 1, height: 16, color: Noct.n700),
                  Positioned(
                    left: leanDeg < 0 ? halfWidth - fillWidth : halfWidth,
                    child: Container(
                      width: fillWidth,
                      height: 8,
                      decoration: BoxDecoration(color: Noct.accent, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
