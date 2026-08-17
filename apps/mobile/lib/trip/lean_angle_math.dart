import 'dart:math' as math;

/// The angle in degrees between two 3D vectors, via the dot-product
/// identity cosθ = (a·b)/(|a||b|). Used by trip/lean_angle_tracker.dart
/// to measure how far the phone has tilted from a calibrated reference
/// orientation — deliberately vector-based (not "read the X axis") so it
/// doesn't need to assume which way the phone is mounted, just that it's
/// mounted rigidly to the bike at all.
double angleBetweenVectorsDeg({
  required double x1,
  required double y1,
  required double z1,
  required double x2,
  required double y2,
  required double z2,
}) {
  final dot = x1 * x2 + y1 * y2 + z1 * z2;
  final mag1 = math.sqrt(x1 * x1 + y1 * y1 + z1 * z1);
  final mag2 = math.sqrt(x2 * x2 + y2 * y2 + z2 * z2);
  if (mag1 == 0 || mag2 == 0) return 0;
  var cosAngle = dot / (mag1 * mag2);
  // Floating-point drift can push this a hair past +/-1, which acos()
  // turns into NaN rather than clamping itself.
  if (cosAngle > 1) cosAngle = 1;
  if (cosAngle < -1) cosAngle = -1;
  return math.acos(cosAngle) * 180 / math.pi;
}
