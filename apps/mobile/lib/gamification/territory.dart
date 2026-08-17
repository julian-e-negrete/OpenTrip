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
