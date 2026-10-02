import '../data/models/trip_point.dart';
import 'geo_math.dart';

/// What a ride-analysis map colors the route by — see
/// trips/ride_analysis_section.dart.
enum RideMetric { speed, lean }

/// The best lean reading a point has: the bike's own IMU (BLE) when
/// connected, otherwise the phone-accelerometer estimate. Magnitude only —
/// the phone tracker is unsigned, so BLE's sign is dropped too for a
/// consistent scale on one map.
double? effectiveLeanDeg(TripPoint p) => p.bleLeanDeg?.abs() ?? p.phoneLeanDeg;

/// The best speed reading a point has: the bike's speedometer when
/// connected (exact, no GPS lag), otherwise GPS speed.
double? effectiveSpeedKph(TripPoint p) => p.bleSpeedKph ?? p.speedKph;

double? metricValue(TripPoint p, RideMetric metric) => switch (metric) {
  RideMetric.speed => effectiveSpeedKph(p),
  RideMetric.lean => effectiveLeanDeg(p),
};

/// Whether any point in [points] has a reading for [metric] — the
/// analysis section hides the Lean tab for rides with no lean data at all.
bool hasMetric(List<TripPoint> points, RideMetric metric) => points.any((p) => metricValue(p, metric) != null);

/// A run of consecutive points whose values fall in the same color
/// bucket — drawn as one polyline, so a long ride becomes a few dozen
/// polylines instead of one per GPS fix.
class RouteSegment {
  /// Indices into the source point list, inclusive on both ends; adjacent
  /// segments share their boundary point so the drawn line has no gaps.
  final int startIndex;
  final int endIndex;

  /// 0..1 position of this segment's value along the color scale, or null
  /// when the points have no reading (drawn in a neutral color).
  final double? level;

  const RouteSegment({required this.startIndex, required this.endIndex, required this.level});
}

/// The value range a metric's color scale spans: 0 to the ride's own max
/// (so a gentle commute still uses the whole palette), floored so a
/// near-stationary ride doesn't stretch a 3 km/h wobble into red.
double scaleMaxFor(List<TripPoint> points, RideMetric metric) {
  var max = 0.0;
  for (final p in points) {
    final v = metricValue(p, metric);
    if (v != null && v > max) max = v;
  }
  final floor = metric == RideMetric.speed ? 30.0 : 15.0;
  return max < floor ? floor : max;
}

/// Splits a route into same-bucket runs for [metric], quantized to
/// [buckets] steps between 0 and [scaleMax].
List<RouteSegment> segmentRoute(
  List<TripPoint> points,
  RideMetric metric, {
  required double scaleMax,
  int buckets = 8,
}) {
  if (points.length < 2) return const [];
  int? bucketOf(TripPoint p) {
    final v = metricValue(p, metric);
    if (v == null) return null;
    final b = (v / scaleMax * buckets).floor();
    return b.clamp(0, buckets - 1);
  }

  final segments = <RouteSegment>[];
  var start = 0;
  var current = bucketOf(points[0]);
  for (var i = 1; i < points.length; i++) {
    final b = bucketOf(points[i]);
    if (b != current) {
      segments.add(RouteSegment(startIndex: start, endIndex: i, level: _levelOf(current, buckets)));
      start = i;
      current = b;
    }
  }
  if (start < points.length - 1) {
    segments.add(RouteSegment(startIndex: start, endIndex: points.length - 1, level: _levelOf(current, buckets)));
  }
  return segments;
}

double? _levelOf(int? bucket, int buckets) => bucket == null ? null : (bucket + 0.5) / buckets;

/// One corner of a ride: a continuous stretch leaned past the detection
/// threshold, summarized by its deepest point.
class Corner {
  final int peakIndex;
  final double peakLeanDeg;

  /// Speed at the moment of peak lean — "how fast through the apex."
  final double? apexSpeedKph;
  final int startIndex;
  final int endIndex;

  const Corner({
    required this.peakIndex,
    required this.peakLeanDeg,
    required this.apexSpeedKph,
    required this.startIndex,
    required this.endIndex,
  });
}

/// Finds corners as stretches where lean stays at or above
/// [thresholdDeg], allowing gaps of up to [maxGapPoints] points under it
/// (one noisy reading mid-corner shouldn't split it into two). Sorted
/// deepest first.
List<Corner> detectCorners(List<TripPoint> points, {double thresholdDeg = 15, int maxGapPoints = 1}) {
  final corners = <Corner>[];
  int? start;
  int? peak;
  var lastAbove = -1;

  void close() {
    if (start != null && peak != null) {
      corners.add(
        Corner(
          peakIndex: peak!,
          peakLeanDeg: effectiveLeanDeg(points[peak!])!,
          apexSpeedKph: effectiveSpeedKph(points[peak!]),
          startIndex: start!,
          endIndex: lastAbove,
        ),
      );
    }
    start = null;
    peak = null;
  }

  for (var i = 0; i < points.length; i++) {
    final lean = effectiveLeanDeg(points[i]);
    final above = lean != null && lean >= thresholdDeg;
    if (above) {
      start ??= i;
      if (peak == null || lean > effectiveLeanDeg(points[peak!])!) peak = i;
      lastAbove = i;
    } else if (start != null && i - lastAbove > maxGapPoints) {
      close();
    }
  }
  close();
  corners.sort((a, b) => b.peakLeanDeg.compareTo(a.peakLeanDeg));
  return corners;
}

/// Index of the route point nearest to a tapped map position — what the
/// analysis map's tap-to-inspect readout shows. Null if [points] is empty
/// or the nearest point is further than [maxMeters] (a tap well off the
/// route shouldn't select anything).
int? nearestPointIndex(List<TripPoint> points, double lat, double lon, {double maxMeters = 150}) {
  int? best;
  var bestMeters = double.infinity;
  for (var i = 0; i < points.length; i++) {
    final m = haversineMeters(lat1: lat, lon1: lon, lat2: points[i].latitude, lon2: points[i].longitude);
    if (m < bestMeters) {
      bestMeters = m;
      best = i;
    }
  }
  return bestMeters <= maxMeters ? best : null;
}
