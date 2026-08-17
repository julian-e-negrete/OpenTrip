import 'dart:async';
import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/models/trip_point.dart';
import '../logging/log_buffer.dart';
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
/// Every stage logs to logBuffer (the same buffer the BLE "Logs" screen
/// shows — see screens/log_screen.dart) since a silent GPS failure is
/// otherwise invisible: unlike a BLE connect failure, there's no
/// exception dialog, just a trip that saves with 0 km recorded.
class LocationRecorder {
  final _pointsController = StreamController<TripPoint>.broadcast();
  final _statsController = StreamController<RecordingStats>.broadcast();

  StreamSubscription<Position>? _positionSub;
  String? _tripId;
  DateTime? _startedAt;
  int _seq = 0;
  double _distanceMeters = 0;
  double? _maxSpeedKph;
  TripPoint? _lastAcceptedPoint;
  int _rejectedAccuracyCount = 0;
  int _rejectedGlitchCount = 0;

  Stream<TripPoint> get pointStream => _pointsController.stream;
  Stream<RecordingStats> get statsStream => _statsController.stream;

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

    logBuffer.add('GPS: starting position stream (${Platform.operatingSystem})');
    _positionSub = Geolocator.getPositionStream(locationSettings: _buildLocationSettings()).listen(
      _onPosition,
      onError: (Object error, StackTrace stack) {
        logBuffer.add('GPS: position stream ERROR: $error');
      },
      onDone: () {
        logBuffer.add('GPS: position stream closed (accepted=$_seq accuracy-rejected=$_rejectedAccuracyCount glitch-rejected=$_rejectedGlitchCount)');
      },
    );
  }

  /// Platform-specific settings so a recording keeps streaming positions
  /// while backgrounded, per this class's doc comment.
  LocationSettings _buildLocationSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 3,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'OpenTrip is recording',
          notificationText: 'Tracking your trip — tap to return to the app.',
          enableWakeLock: true,
        ),
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
    await _pointsController.close();
    await _statsController.close();
  }
}
