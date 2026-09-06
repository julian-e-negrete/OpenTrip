import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/models/trip_point.dart';
import '../logging/error_reporter.dart';
import '../logging/log_buffer.dart';
import 'camera_alerts.dart';
import 'driving_math.dart';
import 'geo_math.dart';

class RecordingStats {
  final Duration elapsed;
  final double distanceMeters;
  final double? currentSpeedKph;
  final double? maxSpeedKph;
  final int pointCount;

  const RecordingStats({
    required this.elapsed,
    required this.distanceMeters,
    required this.currentSpeedKph,
    required this.maxSpeedKph,
    required this.pointCount,
  });

  double get avgSpeedKph {
    final hours = elapsed.inMilliseconds / 3600000.0;
    if (hours <= 0) return 0;
    return (distanceMeters / 1000.0) / hours;
  }
}

/// Fixes less accurate than this (meters) are dropped — filters out the
/// wildly-off readings GPS gives right after lock or near tall buildings.
const _maxAcceptableAccuracyMeters = 30.0;

/// A segment implying faster than this between two consecutive fixes is
/// treated as a GPS glitch, not real movement, and dropped from the
/// distance total (though still recorded as a point).
const _maxPlausibleSpeedKph = 300.0;

/// Driving-behavior thresholds (trip/driving_math.dart) — first guesses,
/// not measurements. Roughly in line with what published telematics
/// literature calls "harsh" (typically 0.3-0.4g), but there's no way to
/// actually tune numbers like these without real driving data.
const _hardAccelThresholdMps2 = 3.5;
const _hardBrakeThresholdMps2 = 4.0;
const _hardCorneringThresholdMps2 = 4.0;

/// Below this speed, GPS course-over-ground is too unreliable to treat a
/// heading change as real cornering rather than noise (see
/// Position.heading's own doc comment) — longitudinal (accel/brake)
/// detection has no such gate, since GPS speed itself stays meaningful
/// down to a stop, and pulling away hard from a stop is exactly the kind
/// of event worth catching.
const _minSpeedForCorneringKph = 8.0;

/// Wraps geolocator's position stream into trip-shaped output: a stream of
/// [TripPoint]s to persist and a stream of running [RecordingStats] for
/// the UI. Distance is accumulated incrementally rather than recomputed
/// from scratch each fix, so recording stays cheap on a long trip.
///
/// Survives backgrounding on Android via geolocator's own foreground-
/// service integration (see [_buildLocationSettings]) — no separate
/// background-service plugin or isolate needed, and no extra BLE code
/// either: once Android stops treating this app as killable (which is
/// what a foreground service buys), the Kawasaki BLE connection
/// (vehicle/kawasaki_connector.dart) survives right along with it, since
/// it lives in the same process. Deliberately doesn't request the
/// heavier "Allow location all the time" (`ACCESS_BACKGROUND_LOCATION`)
/// permission — Android treats an app showing an active foreground-
/// service notification as foregrounded for location purposes, so the
/// ordinary "while using the app" grant this already requests is
/// enough. That's also a real product decision, not just less
/// friction: Play Store policy requires a background-location
/// declaration/review for apps that use `ACCESS_BACKGROUND_LOCATION`,
/// which the foreground-service approach avoids entirely.
///
/// Every stage logs to [logBuffer] (the same buffer screens/log_screen.dart
/// shows) since a silent GPS failure is otherwise invisible: unlike a BLE
/// connect failure, there's no exception dialog, just a trip that saves
/// with 0 km recorded.
///
/// Also drives speed/red-light-camera proximity alerts
/// (trip/camera_alerts.dart) and driving-behavior stats
/// (trip/driving_math.dart — acceleration, braking, cornering) off the
/// same position stream — built into the recorder itself, not
/// trip/recording_screen.dart, so both come for free.
class LocationRecorder {
  /// False when this recorder runs inside a process that's already kept
  /// alive by its own foreground service. Currently always true — every
  /// caller today is trip/recording_screen.dart's own manually-driven
  /// recording — but kept as a parameter rather than hardcoded, since
  /// AndroidSettings.foregroundNotificationConfig genuinely does need to
  /// be skippable for any future caller that already owns its own
  /// foreground service.
  final bool showForegroundNotification;

  LocationRecorder({this.showForegroundNotification = true});

  final _pointsController = StreamController<TripPoint>.broadcast();
  final _statsController = StreamController<RecordingStats>.broadcast();
  final _cameraAlerts = CameraAlertService();

  StreamSubscription<Position>? _positionSub;
  String? _tripId;
  DateTime? _startedAt;
  int _seq = 0;

  /// Independent of GPS fixes arriving at all — see [_tick]'s doc
  /// comment for why this has to exist.
  Timer? _tickTimer;
  double? _lastSpeedKph;
  double _distanceMeters = 0;
  double? _maxSpeedKph;
  TripPoint? _lastAcceptedPoint;
  int _rejectedAccuracyCount = 0;
  int _rejectedGlitchCount = 0;

  // Driving-behavior stats (trip/driving_math.dart) — GPS-derived, so
  // available for every vehicle, not just BLE-equipped bikes. _lastHeadingDeg
  // is tracked separately from _lastAcceptedPoint since TripPoint itself
  // doesn't persist heading (only needed transiently for this).
  double? _lastHeadingDeg;
  double? _maxAccelMps2;
  double? _maxBrakeMps2;
  double? _maxCorneringMps2;
  int _hardAccelCount = 0;
  int _hardBrakeCount = 0;
  int _hardCorneringCount = 0;

  double? get behaviorMaxAccelG => _maxAccelMps2 == null ? null : mps2ToG(_maxAccelMps2!);
  double? get behaviorMaxBrakeG => _maxBrakeMps2 == null ? null : mps2ToG(_maxBrakeMps2!);
  double? get behaviorMaxCorneringG => _maxCorneringMps2 == null ? null : mps2ToG(_maxCorneringMps2!);
  int get behaviorHardAccelCount => _hardAccelCount;
  int get behaviorHardBrakeCount => _hardBrakeCount;
  int get behaviorHardCorneringCount => _hardCorneringCount;

  Stream<TripPoint> get pointStream => _pointsController.stream;
  Stream<RecordingStats> get statsStream => _statsController.stream;

  /// Speed/red-light-camera proximity alerts — see trip/camera_alerts.dart.
  /// Built into the recorder itself rather than trip/recording_screen.dart
  /// wiring its own.
  Stream<CameraAlert> get cameraAlertStream => _cameraAlerts.alerts;

  /// The cameras loaded for the current stretch, so the map can plot them
  /// ahead of time — see trip/camera_alerts.dart.
  ValueListenable<List<CameraPoint>> get camerasNotifier => _cameraAlerts.camerasNotifier;

  /// Loads cameras near [position] for the idle (not-yet-recording) map —
  /// see CameraAlertService.loadNear.
  Future<void> loadCamerasNear(Position position) => _cameraAlerts.loadNear(position);

  bool get isRecording => _positionSub != null;

  /// Checks location services + permission, requesting if needed. Throws a
  /// descriptive [StateError] instead of surfacing a raw plugin exception.
  static Future<void> ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      logBuffer.add('GPS: location services are OFF');
      throw StateError('Location services are off — enable them in system settings.');
    }
    var permission = await Geolocator.checkPermission();
    logBuffer.add('GPS: location permission is $permission');
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      logBuffer.add('GPS: location permission after request: $permission');
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw StateError('Location permission denied — grant it in system settings to record a trip.');
    }

    // Android 13+ requires this to actually show the foreground-service
    // notification (see _buildLocationSettings) — without it, some
    // geolocator/Android versions fail the whole foreground service
    // startup silently, which stops position updates from ever arriving
    // even though permission and location services are otherwise fine.
    if (Platform.isAndroid) {
      final notificationStatus = await Permission.notification.status;
      logBuffer.add('GPS: notification permission is $notificationStatus');
      if (notificationStatus.isDenied) {
        final result = await Permission.notification.request();
        logBuffer.add('GPS: notification permission after request: $result');
      }
    }
  }

  Future<void> start(String tripId) async {
    if (isRecording) return;
    await ensureReady();

    _tripId = tripId;
    _startedAt = DateTime.now();
    _seq = 0;
    _distanceMeters = 0;
    _maxSpeedKph = null;
    _lastAcceptedPoint = null;
    _rejectedAccuracyCount = 0;
    _rejectedGlitchCount = 0;
    _cameraAlerts.resetForNewTrip();
    _lastHeadingDeg = null;
    _maxAccelMps2 = null;
    _maxBrakeMps2 = null;
    _maxCorneringMps2 = null;
    _hardAccelCount = 0;
    _hardBrakeCount = 0;
    _hardCorneringCount = 0;

    logBuffer.add('GPS: starting position stream (${Platform.operatingSystem})');
    _positionSub = Geolocator.getPositionStream(locationSettings: _buildLocationSettings()).listen(
      _onPosition,
      onError: (Object error, StackTrace stack) {
        logBuffer.add('GPS: position stream ERROR: $error');
        unawaited(ErrorReporter.report('GPS: position stream', error, stack));
      },
      onDone: () {
        logBuffer.add('GPS: position stream closed (accepted=$_seq accuracy-rejected=$_rejectedAccuracyCount glitch-rejected=$_rejectedGlitchCount)');
      },
    );
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// A [RecordingStats] update wasn't otherwise guaranteed at any
  /// particular rate — [_onPosition] only fires when a new fix actually
  /// arrives, which [_buildLocationSettings]'s `distanceFilter: 3` means
  /// it doesn't while stopped (parked, waiting at a light, or just
  /// hasn't pulled away yet). Elapsed time is wall-clock, not something
  /// that should ever depend on movement, so the whole display —
  /// including the clock — read as hung any time the rider wasn't
  /// currently moving. This ticks once a second regardless, recomputing
  /// elapsed live and re-emitting whatever distance/speed the last real
  /// fix reported.
  void _tick() {
    final startedAt = _startedAt;
    if (startedAt == null) return;
    _statsController.add(
      RecordingStats(
        elapsed: DateTime.now().difference(startedAt),
        distanceMeters: _distanceMeters,
        currentSpeedKph: _lastSpeedKph,
        maxSpeedKph: _maxSpeedKph,
        pointCount: _seq,
      ),
    );
  }

  /// Platform-specific settings so a recording keeps streaming positions
  /// while backgrounded, per this class's doc comment.
  LocationSettings _buildLocationSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 3,
        // geolocator_android defaults this to 5000ms when left unset —
        // independent of distanceFilter, so even riding fast enough to
        // clear 3m in well under a second still only got a fix every 5s,
        // making live speed/position feel laggy rather than tracking in
        // real time. 1s matches a real speedometer's update rate.
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: showForegroundNotification
            ? const ForegroundNotificationConfig(
                notificationTitle: 'OpenTrip is recording',
                notificationText: 'Tracking your trip — tap to return to the app.',
                enableWakeLock: true,
              )
            : null,
      );
    }
    if (Platform.isIOS) {
      // Unverified — this project has no way to build/run iOS (needs a
      // Mac; see /README.md). Requires Info.plist's
      // UIBackgroundModes=[location] and NSLocationAlwaysAndWhenInUseUsageDescription
      // (apps/mobile/ios/Runner/Info.plist), and the OS granting "Always"
      // location access, not just "While Using the App" — geolocator
      // silently ignores allowBackgroundLocationUpdates without that.
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 3,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 3);
  }

  void _onPosition(Position position) {
    // Camera-proximity checking gets every raw fix, independent of the
    // stricter accuracy/glitch filtering below — a 500m alert radius
    // (trip/camera_alerts.dart) doesn't need the same precision as
    // distance accumulation does.
    unawaited(_cameraAlerts.onPosition(position));

    if (position.accuracy > _maxAcceptableAccuracyMeters) {
      _rejectedAccuracyCount++;
      logBuffer.add(
        'GPS: fix rejected, accuracy ${position.accuracy.toStringAsFixed(0)}m '
        '> ${_maxAcceptableAccuracyMeters.toStringAsFixed(0)}m threshold '
        '(${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)})',
      );
      return;
    }

    final speedKph = position.speed >= 0 ? position.speed * 3.6 : null;
    final now = DateTime.now();

    final last = _lastAcceptedPoint;
    if (last != null) {
      final segmentMeters = haversineMeters(
        lat1: last.latitude,
        lon1: last.longitude,
        lat2: position.latitude,
        lon2: position.longitude,
      );
      final seconds = now.difference(last.timestamp).inMilliseconds / 1000.0;
      if (seconds > 0 && (segmentMeters / seconds) * 3.6 > _maxPlausibleSpeedKph) {
        _rejectedGlitchCount++;
        logBuffer.add(
          'GPS: fix rejected as a glitch, implied ${((segmentMeters / seconds) * 3.6).toStringAsFixed(0)} km/h',
        );
        return; // GPS glitch — skip this fix entirely rather than pollute the trip
      }
      _distanceMeters += segmentMeters;

      if (seconds > 0 && speedKph != null && last.speedKph != null) {
        final longAccel = longitudinalAccelMps2(
          speedBeforeKph: last.speedKph!,
          speedAfterKph: speedKph,
          dtSeconds: seconds,
        );
        if (longAccel > _hardAccelThresholdMps2) {
          _hardAccelCount++;
          if (_maxAccelMps2 == null || longAccel > _maxAccelMps2!) _maxAccelMps2 = longAccel;
        } else if (longAccel < -_hardBrakeThresholdMps2) {
          _hardBrakeCount++;
          final magnitude = longAccel.abs();
          if (_maxBrakeMps2 == null || magnitude > _maxBrakeMps2!) _maxBrakeMps2 = magnitude;
        }

        final lastHeading = _lastHeadingDeg;
        final avgSpeedKph = (last.speedKph! + speedKph) / 2;
        if (lastHeading != null && avgSpeedKph >= _minSpeedForCorneringKph) {
          final lateralAccel = lateralAccelMps2(
            headingBeforeDeg: lastHeading,
            headingAfterDeg: position.heading,
            avgSpeedKph: avgSpeedKph,
            dtSeconds: seconds,
          );
          if (lateralAccel > _hardCorneringThresholdMps2) {
            _hardCorneringCount++;
            if (_maxCorneringMps2 == null || lateralAccel > _maxCorneringMps2!) _maxCorneringMps2 = lateralAccel;
          }
        }
      }
      _lastHeadingDeg = position.heading;
    }

    final point = TripPoint(
      tripId: _tripId!,
      seq: _seq++,
      latitude: position.latitude,
      longitude: position.longitude,
      altitudeMeters: position.altitude,
      speedKph: speedKph,
      timestamp: now,
    );
    _lastAcceptedPoint = point;

    if (speedKph != null && (_maxSpeedKph == null || speedKph > _maxSpeedKph!)) {
      _maxSpeedKph = speedKph;
    }
    _lastSpeedKph = speedKph;

    if (_seq == 1 || _seq % 20 == 0) {
      logBuffer.add(
        'GPS: fix #$_seq accepted, accuracy ${position.accuracy.toStringAsFixed(0)}m, '
        'distance so far ${(_distanceMeters / 1000).toStringAsFixed(2)}km',
      );
    }

    _pointsController.add(point);
    _statsController.add(
      RecordingStats(
        elapsed: now.difference(_startedAt!),
        distanceMeters: _distanceMeters,
        currentSpeedKph: speedKph,
        maxSpeedKph: _maxSpeedKph,
        pointCount: _seq,
      ),
    );
  }

  /// Stops the GPS stream and returns final stats for the caller to persist
  /// via TripRepository.finishTrip.
  Future<RecordingStats> stop() async {
    logBuffer.add(
      'GPS: stopping — accepted=$_seq accuracy-rejected=$_rejectedAccuracyCount '
      'glitch-rejected=$_rejectedGlitchCount distance=${(_distanceMeters / 1000).toStringAsFixed(2)}km',
    );
    await _positionSub?.cancel();
    _positionSub = null;
    _tickTimer?.cancel();
    _tickTimer = null;
    final elapsed = _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);
    return RecordingStats(
      elapsed: elapsed,
      distanceMeters: _distanceMeters,
      currentSpeedKph: null,
      maxSpeedKph: _maxSpeedKph,
      pointCount: _seq,
    );
  }

  Future<void> dispose() async {
    await _positionSub?.cancel();
    _tickTimer?.cancel();
    await _pointsController.close();
    await _statsController.close();
    await _cameraAlerts.dispose();
  }
}
