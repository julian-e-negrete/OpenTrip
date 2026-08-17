import '../data/models/trip_point.dart';

/// Where the replay marker sits at [progress] (0.0 at the first point,
/// 1.0 at the last) — interpolated linearly between the two GPS fixes
/// bracketing that moment in *real elapsed time*, not by point index.
/// A trip that idled at a red light has points bunched up in time there
/// and sparse on the open road after it; indexing by position in the
/// list would replay the traffic jam and the highway stretch at the same
/// speed, which isn't what actually happened.
(double lat, double lon) positionAtProgress(List<TripPoint> points, double progress) {
  if (points.isEmpty) return (0, 0);
  if (points.length == 1) return (points.first.latitude, points.first.longitude);

  final clamped = progress < 0 ? 0.0 : (progress > 1 ? 1.0 : progress);
  final totalMs = points.last.timestamp.difference(points.first.timestamp).inMilliseconds;
  if (totalMs <= 0) return (points.last.latitude, points.last.longitude);
  final targetMs = totalMs * clamped;

  for (var i = 1; i < points.length; i++) {
    final tMs = points[i].timestamp.difference(points.first.timestamp).inMilliseconds;
    if (tMs >= targetMs) {
      final prev = points[i - 1];
      final prevMs = prev.timestamp.difference(points.first.timestamp).inMilliseconds;
      final segmentFraction = tMs == prevMs ? 0.0 : (targetMs - prevMs) / (tMs - prevMs);
      final lat = prev.latitude + (points[i].latitude - prev.latitude) * segmentFraction;
      final lon = prev.longitude + (points[i].longitude - prev.longitude) * segmentFraction;
      return (lat, lon);
    }
  }
  return (points.last.latitude, points.last.longitude);
}

/// How many of [points], counted from the start, fall at or before
/// [progress] in elapsed time — the prefix to draw as "traveled so far"
/// behind the replay marker.
int pointCountAtProgress(List<TripPoint> points, double progress) {
  if (points.length < 2) return points.length;
  final clamped = progress < 0 ? 0.0 : (progress > 1 ? 1.0 : progress);
  final totalMs = points.last.timestamp.difference(points.first.timestamp).inMilliseconds;
  if (totalMs <= 0) return points.length;
  final targetMs = totalMs * clamped;

  var count = 1;
  for (var i = 1; i < points.length; i++) {
    final tMs = points[i].timestamp.difference(points.first.timestamp).inMilliseconds;
    if (tMs > targetMs) break;
    count++;
  }
  return count;
}
