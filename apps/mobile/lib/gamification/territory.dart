import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/models/trip_point.dart';

/// Roughly 1.1km per cell at the equator (a degree of latitude is ~111km
/// everywhere; a degree of longitude shrinks toward the poles, so cells
/// get narrower — not equal-area). That's a deliberate simplification,
/// not a bug: real equal-area tiling (e.g. a proper geohash/S2 scheme)
/// is a lot more code for a "how much new ground have you covered"
/// bragging-rights stat that doesn't need to be precise, only consistent
/// for one rider over time. Matches TripRank's "territory explored"
/// leaderboard category (see /README.md's "Why this exists").
const _cellSizeDeg = 0.01;

/// Which grid cell a coordinate falls in, as a stable string key so it
/// can be a SQLite/Postgres primary key column directly.
String cellKeyFor(double latitude, double longitude) {
  final latCell = (latitude / _cellSizeDeg).floor();
  final lngCell = (longitude / _cellSizeDeg).floor();
  return '$latCell:$lngCell';
}

/// Every distinct cell a trip's route passed through.
Set<String> cellsForTrip(Iterable<TripPoint> points) {
  return points.map((p) => cellKeyFor(p.latitude, p.longitude)).toSet();
}

/// The inverse of [cellKeyFor] — the rectangle a cell key covers, for
/// drawing it on a map (see gamification/territory_map_screen.dart).
LatLngBounds cellBoundsFor(String cellKey) {
  final parts = cellKey.split(':');
  final latCell = int.parse(parts[0]);
  final lngCell = int.parse(parts[1]);
  return LatLngBounds(
    LatLng(latCell * _cellSizeDeg, lngCell * _cellSizeDeg),
    LatLng((latCell + 1) * _cellSizeDeg, (lngCell + 1) * _cellSizeDeg),
  );
}
