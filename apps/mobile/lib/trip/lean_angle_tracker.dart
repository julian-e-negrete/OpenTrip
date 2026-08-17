import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

import 'lean_angle_math.dart';

/// Best-effort motorcycle lean-angle tracking from the phone's own
/// accelerometer — for any bike, not just BLE-connected Kawasakis (which
/// already get a real lean-angle reading straight from the bike's own
/// IMU — see data/models/trip.dart's `bleMaxLeanDeg`).
///
/// **Requires the phone mounted rigidly to the bike** (handlebar/tank
/// mount) — not handheld, not in a pocket. Unlike trip/driving_math.dart's
/// GPS-derived stats (deliberately built to work no matter where the
/// phone is), lean angle has no GPS-only equivalent — the accelerometer
/// is the only sensor that can see it at all, so this trades "works
/// anywhere" for "works if actually mounted." A phone in a pocket would
/// still produce numbers that *look* like a real lean-angle reading —
/// worse than not having the feature at all — which is why this is
/// opt-in (trip/recording_screen.dart's "Track lean angle" toggle), not
/// silently always-on the way camera alerts and driving-behavior stats
/// are.
///
/// Method: averages the first [_calibrationWindow] of readings into a
/// reference gravity vector (assumes the bike is upright and roughly
/// stationary right as recording starts), then reports the angle
/// between each subsequent reading and that reference — the phone's
/// total tilt from however it sat at calibration — smoothed with a
/// simple exponential moving average to damp road-vibration noise.
/// Deliberately doesn't try to isolate roll from pitch (a wheelie or a
/// hard-braking dive reads as "lean" too) or fuse in the gyroscope — a
/// single accelerometer reading can't cleanly tell those apart, and a
/// fake-precise filter pretending otherwise would be worse than an
/// honestly-approximate one. Good enough for a bragging-rights max-lean
/// stat, not a substitute for the bike's own IMU.
class LeanAngleTracker {
  static const _calibrationWindow = Duration(milliseconds: 800);
  static const _smoothingAlpha = 0.3; // higher = less smoothing, more noise

  StreamSubscription<AccelerometerEvent>? _sub;
  final _controller = StreamController<double>.broadcast();

  /// Smoothed current lean angle in degrees, for a live readout while
  /// recording — see trip/recording_screen.dart's "Lean" stat tile.
  Stream<double> get angleStream => _controller.stream;

  (double, double, double)? _reference;
  double? _smoothedX;
  double? _smoothedY;
  double? _smoothedZ;
  double _maxAngleDeg = 0;
  DateTime? _startedAt;

  double get maxAngleDeg => _maxAngleDeg;

  bool get isTracking => _sub != null;

  Future<void> start() async {
    if (isTracking) return;
    _reference = null;
    _smoothedX = null;
    _smoothedY = null;
    _smoothedZ = null;
    _maxAngleDeg = 0;
    _startedAt = DateTime.now();
    _sub = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen(_onEvent);
  }

  void _onEvent(AccelerometerEvent event) {
    // Smooth before anything else, so a single vibration spike during
    // the calibration window doesn't become the reference itself.
    final smoothedX = _smoothedX;
    if (smoothedX == null) {
      _smoothedX = event.x;
      _smoothedY = event.y;
      _smoothedZ = event.z;
    } else {
      _smoothedX = smoothedX + _smoothingAlpha * (event.x - smoothedX);
      _smoothedY = _smoothedY! + _smoothingAlpha * (event.y - _smoothedY!);
      _smoothedZ = _smoothedZ! + _smoothingAlpha * (event.z - _smoothedZ!);
    }

    final startedAt = _startedAt;
    if (startedAt != null && DateTime.now().difference(startedAt) < _calibrationWindow) {
      return; // still calibrating — don't report or count toward max yet
    }

    final reference = _reference;
    if (reference == null) {
      _reference = (_smoothedX!, _smoothedY!, _smoothedZ!);
      return;
    }

    final (refX, refY, refZ) = reference;
    final angle = angleBetweenVectorsDeg(
      x1: _smoothedX!,
      y1: _smoothedY!,
      z1: _smoothedZ!,
      x2: refX,
      y2: refY,
      z2: refZ,
    );
    if (angle > _maxAngleDeg) _maxAngleDeg = angle;
    _controller.add(angle);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
