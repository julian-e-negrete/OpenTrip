import 'dart:math' as math;
import 'dart:ui';

/// Reduces a GPS track to its shape-defining points via the
/// Ramer–Douglas–Peucker algorithm, then fits it into a small box —
/// what the Trips list's route thumbnails (design handoff §1) and
/// Vehicle detail's "recent trips" route glyphs are built from.
/// Operates on raw `(lat, lon)` pairs rather than [TripPoint] so it has
/// no dependency on the data layer.
typedef LatLon = (double lat, double lon);

List<LatLon> simplifyRoute(List<LatLon> points, {double epsilon = 0.00006}) {
  if (points.length < 3) return points;
  final keep = List<bool>.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;
  _simplifySegment(points, 0, points.length - 1, epsilon, keep);
  return [for (var i = 0; i < points.length; i++) if (keep[i]) points[i]];
}

void _simplifySegment(List<LatLon> pts, int first, int last, double epsilon, List<bool> keep) {
  if (last <= first + 1) return;
  var maxDist = 0.0;
  var split = first;
  final (aLat, aLon) = pts[first];
  final (bLat, bLon) = pts[last];
  for (var i = first + 1; i < last; i++) {
    final d = _perpendicularDistance(pts[i], aLat, aLon, bLat, bLon);
    if (d > maxDist) {
      maxDist = d;
      split = i;
    }
  }
  if (maxDist > epsilon) {
    keep[split] = true;
    _simplifySegment(pts, first, split, epsilon, keep);
    _simplifySegment(pts, split, last, epsilon, keep);
  }
}

double _perpendicularDistance(LatLon p, double aLat, double aLon, double bLat, double bLon) {
  final (pLat, pLon) = p;
  final dx = bLon - aLon;
  final dy = bLat - aLat;
  final lenSq = dx * dx + dy * dy;
  if (lenSq == 0) return math.sqrt(math.pow(pLon - aLon, 2) + math.pow(pLat - aLat, 2));
  final t = (((pLon - aLon) * dx) + ((pLat - aLat) * dy)) / lenSq;
  final projLon = aLon + t.clamp(0.0, 1.0) * dx;
  final projLat = aLat + t.clamp(0.0, 1.0) * dy;
  return math.sqrt(math.pow(pLon - projLon, 2) + math.pow(pLat - projLat, 2));
}

/// Projects (equirectangular — plenty accurate at thumbnail scale) and
/// fits [points] into [size] with [inset] padding on every side,
/// preserving aspect ratio, flipping latitude so north is up.
List<Offset> fitRouteToBox(List<LatLon> points, Size size, double inset) {
  if (points.isEmpty) return const [];
  if (points.length == 1) return [Offset(size.width / 2, size.height / 2)];

  var minLat = points.first.$1, maxLat = points.first.$1;
  var minLon = points.first.$2, maxLon = points.first.$2;
  for (final (lat, lon) in points) {
    if (lat < minLat) minLat = lat;
    if (lat > maxLat) maxLat = lat;
    if (lon < minLon) minLon = lon;
    if (lon > maxLon) maxLon = lon;
  }
  final latRange = (maxLat - minLat).abs() < 1e-9 ? 1e-9 : maxLat - minLat;
  final lonRange = (maxLon - minLon).abs() < 1e-9 ? 1e-9 : maxLon - minLon;
  final drawableW = size.width - inset * 2;
  final drawableH = size.height - inset * 2;
  // Longitude degrees are narrower than latitude degrees away from the
  // equator; scale x by cos(latitude) so the thumbnail isn't stretched.
  final latMid = (minLat + maxLat) / 2;
  final lonScaleFactor = math.cos(latMid * math.pi / 180).abs().clamp(0.15, 1.0);
  final scale = math.min(drawableW / (lonRange * lonScaleFactor), drawableH / latRange);

  final projectedW = lonRange * lonScaleFactor * scale;
  final projectedH = latRange * scale;
  final offsetX = inset + (drawableW - projectedW) / 2;
  final offsetY = inset + (drawableH - projectedH) / 2;

  return [
    for (final (lat, lon) in points)
      Offset(
        offsetX + (lon - minLon) * lonScaleFactor * scale,
        offsetY + (maxLat - lat) * scale,
      ),
  ];
}
