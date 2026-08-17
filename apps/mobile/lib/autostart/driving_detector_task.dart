import 'dart:async';

import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/current_user.dart';
import '../config/app_config.dart';
import '../data/models/trip.dart';
import '../data/models/trip_point.dart';
import '../data/repositories/trip_repository.dart';
import '../data/repositories/vehicle_repository.dart';
import '../gamification/gamification_service.dart';
import '../trip/camera_alerts.dart';
import '../trip/location_recorder.dart';

/// The message autostart/auto_start_controller.dart sends when the user
/// taps "Stop & save" in trip/recording_screen.dart on a trip this task
/// started — this task is the only one holding the actual running
/// LocationRecorder, so stopping has to be a message, not a local call.
const kStopAutoTripMessage = 'stopAutoTrip';

/// A sustained IN_VEHICLE reading shorter than this is treated as noise
/// (a brief stop at a light, a momentary misclassification) rather than
/// "you started driving" — chosen to be long enough to skip past that,
/// short enough not to annoy someone who really did just start driving.
/// Very likely needs retuning once this runs on a real device; there's no
/// way to validate a debounce window like this without one.
const _startDebounce = Duration(seconds: 45);

/// Sustained STILL/WALKING/RUNNING longer than this ends an auto-started
/// trip — long enough to survive a red light or a quick stop for gas
/// without cutting the trip short, short enough not to keep recording
/// long after a drive is actually over. Same "needs real-device tuning"
/// caveat as [_startDebounce].
const _stopDebounce = Duration(minutes: 3);

/// Runs entirely in a background isolate (flutter_foreground_task), kept
/// alive by its own foreground-service notification independent of
/// trip/location_recorder.dart's — see that file's [LocationRecorder]
/// doc comment on `showForegroundNotification`. Watches
/// ActivityRecognition transitions and starts/stops a trip recording of
/// its own accord, entirely separate from trip/recording_screen.dart's
/// manually-driven LocationRecorder — the two never run at once, since
/// both check TripRepository.activeTripFor before starting (see that
/// method's doc comment for why the database, not in-memory state, is
/// the source of truth here: this isolate and the main UI isolate don't
/// share Dart memory even though they're the same OS process).
///
/// This class only decides *when*; it doesn't touch anything about *how*
/// a trip is recorded beyond wiring LocationRecorder up the same way
/// trip/recording_screen.dart does. BLE telemetry is deliberately not
/// attempted here — connecting to a bike needs the scan/connect flow a
/// background isolate has no reasonable way to drive unattended, so an
/// auto-started trip is always GPS-only; connecting a bike manually
/// still works normally on top of it via the Vehicle tab.
class DrivingDetectorTaskHandler extends TaskHandler {
  StreamSubscription<Activity>? _activitySub;
  LocationRecorder? _recorder;
  StreamSubscription<TripPoint>? _pointSub;
  StreamSubscription<RecordingStats>? _statsSub;
  StreamSubscription<CameraAlert>? _cameraAlertSub;
  final _pointBuffer = <TripPoint>[];

  Trip? _activeTrip;
  RecordingStats? _latestStats;

  DateTime? _inVehicleSince;
  DateTime? _stillSince;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    if (AppConfig.isSupabaseConfigured) {
      // A fresh isolate — main.dart's own Supabase.initialize() ran in a
      // different root isolate and isn't visible here. This restores the
      // persisted session from disk the same way a cold app start does.
      await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
    }

    final permission = await FlutterActivityRecognition.instance.checkPermission();
    if (permission != ActivityPermission.GRANTED) {
      // Can't request it from here — no foreground Activity to show the
      // dialog. autostart/auto_start_controller.dart requests it before
      // ever starting this service, so this should already be granted;
      // this is just a defensive no-op if something revoked it since.
      await FlutterForegroundTask.updateService(
        notificationTitle: 'OpenTrip',
        notificationText: 'Auto-start needs the activity permission — open the app to fix this.',
      );
      return;
    }

    final userId = await CurrentUser.instance.id();
    final existing = await TripRepository.instance.activeTripFor(userId);
    if (existing != null && existing.autoStarted) {
      // The service was restarted mid-trip (OS memory pressure, etc.) —
      // resume it rather than starting a second, competing trip. See
      // LocationRecorder.start's priorPoints doc comment for what this
      // does and doesn't recover.
      await _resumeTrip(existing);
    }

    _activitySub = FlutterActivityRecognition.instance.activityStream.listen(_onActivity);
    _updateIdleNotification();
  }

  @override
  void onReceiveData(Object data) {
    if (data == kStopAutoTripMessage) {
      unawaited(_stopAutoTrip());
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_activeTrip == null) return;
    final stats = _latestStats;
    if (stats == null) return;
    FlutterForegroundTask.updateService(
      notificationTitle: 'OpenTrip is recording',
      notificationText: '${(stats.distanceMeters / 1000).toStringAsFixed(1)} km so far — auto-detected driving',
    );
  }

  void _onActivity(Activity activity) {
    if (activity.confidence == ActivityConfidence.LOW) return;

    final now = DateTime.now();
    switch (activity.type) {
      case ActivityType.IN_VEHICLE:
        _stillSince = null;
        _inVehicleSince ??= now;
        if (_activeTrip == null && now.difference(_inVehicleSince!) >= _startDebounce) {
          unawaited(_startAutoTrip());
        }
        break;
      case ActivityType.STILL:
      case ActivityType.WALKING:
      case ActivityType.RUNNING:
        _inVehicleSince = null;
        _stillSince ??= now;
        if (_activeTrip != null && now.difference(_stillSince!) >= _stopDebounce) {
          unawaited(_stopAutoTrip());
        }
        break;
      case ActivityType.ON_BICYCLE:
      case ActivityType.UNKNOWN:
        // Ambiguous — don't let either debounce accumulate off of it.
        _inVehicleSince = null;
        _stillSince = null;
        break;
    }
  }

  Future<void> _startAutoTrip() async {
    final userId = await CurrentUser.instance.id();
    if (await TripRepository.instance.activeTripFor(userId) != null) return;

    var vehicleId = await TripRepository.instance.mostRecentVehicleId(userId);
    if (vehicleId == null) {
      final vehicles = await VehicleRepository.instance.listForUser(userId);
      vehicleId = vehicles.isEmpty ? null : vehicles.first.id;
    }
    if (vehicleId == null) {
      // Nothing to record onto — stay watching, try again on the next
      // sustained IN_VEHICLE reading (e.g. once a vehicle's been added).
      return;
    }

    final trip = await TripRepository.instance.startTrip(userId: userId, vehicleId: vehicleId, autoStarted: true);
    await _attachRecorder(trip);
    FlutterForegroundTask.sendDataToMain({'event': 'autoTripStarted', 'tripId': trip.id});
  }

  Future<void> _resumeTrip(Trip trip) async {
    final priorPoints = await TripRepository.instance.pointsForTrip(trip.id);
    await _attachRecorder(trip, priorPoints: priorPoints);
  }

  Future<void> _attachRecorder(Trip trip, {List<TripPoint> priorPoints = const []}) async {
    _activeTrip = trip;
    final recorder = LocationRecorder(showForegroundNotification: false);
    _recorder = recorder;
    await recorder.start(trip.id, priorPoints: priorPoints);
    _pointSub = recorder.pointStream.listen((point) {
      _pointBuffer.add(point);
      if (_pointBuffer.length >= 20) unawaited(_flushPoints());
    });
    _statsSub = recorder.statsStream.listen((stats) => _latestStats = stats);
    _cameraAlertSub = recorder.cameraAlertStream.listen(_onCameraAlert);
    await FlutterForegroundTask.updateService(
      notificationTitle: 'OpenTrip is recording',
      notificationText: 'Auto-detected driving — tap to open',
    );
  }

  Future<void> _flushPoints() async {
    if (_pointBuffer.isEmpty) return;
    final toFlush = List<TripPoint>.of(_pointBuffer);
    _pointBuffer.clear();
    await TripRepository.instance.appendPoints(toFlush);
  }

  Future<void> _stopAutoTrip() async {
    final trip = _activeTrip;
    final recorder = _recorder;
    if (trip == null || recorder == null) return;

    final finalStats = await recorder.stop();
    await _pointSub?.cancel();
    await _statsSub?.cancel();
    await _cameraAlertSub?.cancel();
    await _flushPoints();
    await recorder.dispose();

    final finished = trip.finish(
      endedAt: DateTime.now(),
      distanceMeters: finalStats.distanceMeters,
      durationSeconds: finalStats.elapsed.inSeconds,
      avgSpeedKph: finalStats.avgSpeedKph,
      maxSpeedKph: finalStats.maxSpeedKph,
      pointCount: finalStats.pointCount,
    );
    await TripRepository.instance.finishTrip(finished);

    final userId = await CurrentUser.instance.id();
    final points = await TripRepository.instance.pointsForTrip(finished.id);
    // Trophies earned here are still recorded, just not celebrated with
    // the in-app dialog trip/recording_screen.dart shows for a manual
    // stop — there's no screen open to show it to.
    await GamificationService.processFinishedTrip(userId: userId, trip: finished, points: points);

    _activeTrip = null;
    _recorder = null;
    _latestStats = null;
    _inVehicleSince = null;
    _stillSince = null;

    _updateIdleNotification();
    FlutterForegroundTask.sendDataToMain({'event': 'autoTripFinished', 'tripId': finished.id});
  }

  void _onCameraAlert(CameraAlert alert) {
    final label = alert.camera.type == CameraAlertType.redLightCamera ? 'Red light camera' : 'Speed camera';
    // No screen to show this on — the notification text is the only
    // surface available here, alongside the haptic buzz
    // CameraAlertService already triggers itself. Gets overwritten by
    // the next onRepeatEvent tick (up to 30s later) or the next alert;
    // brief enough to be a nudge, not a persistent warning.
    FlutterForegroundTask.updateService(
      notificationTitle: 'OpenTrip is recording',
      notificationText: '⚠ $label ahead',
    );
  }

  void _updateIdleNotification() {
    FlutterForegroundTask.updateService(
      notificationTitle: 'OpenTrip',
      notificationText: 'Watching for driving…',
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _activitySub?.cancel();
    await _pointSub?.cancel();
    await _statsSub?.cancel();
    await _cameraAlertSub?.cancel();
    await _flushPoints();
    await _recorder?.dispose();
    // Deliberately doesn't finish an in-progress trip here — if this is a
    // genuine kill (not the user turning the feature off), the trip stays
    // "active" in the database and _resumeTrip picks it back up the next
    // time this task starts (system restart or the user reopening the
    // app and re-enabling the feature).
  }
}

/// Entry point flutter_foreground_task spawns the background isolate
/// with — must be a top-level function (an instance method won't survive
/// being handed across isolates). See autostart/auto_start_controller.dart.
@pragma('vm:entry-point')
void startDrivingDetectorTask() {
  FlutterForegroundTask.setTaskHandler(DrivingDetectorTaskHandler());
}
