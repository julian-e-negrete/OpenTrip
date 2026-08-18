import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../data/models/trip_point.dart';

/// Flat-topped hexagons, not squares — the same "conquer the map" look
/// TripRank itself uses (a chain of hexagons tracing the road you rode,
/// not a checkerboard of rectangles). [_hexSizeDeg] is the center-to-
/// corner distance, roughly ~390m at the equator (a degree of latitude
/// is ~111km everywhere; a degree of longitude shrinks toward the
/// poles, so hexagons get squashed east-west away from the equator —
/// the same deliberate simplification the original square grid used:
/// not equal-area, doesn't need to be precise, only consistent for one
/// rider over time. Matches TripRank's "territory explored" leaderboard
/// category (see /README.md's "Why this exists").
///
/// Cells are addressed by axial hex coordinates ("q:r" — see Red Blob
/// Games' hexagonal-grid reference for the math this follows) rather
/// than the old row/column pair. A coordinate's hex is found by
/// converting to fractional axial coordinates and rounding via cube
/// coordinates ([_roundAxial]) — the standard technique, since naive
/// per-axis rounding of q and r independently doesn't land on the
/// correct hex near a cell boundary.
const _hexSizeDeg = 0.0035;
const _sqrt3 = 1.7320508075688772;

/// Which hexagonal cell a coordinate falls in, as a stable "q:r" axial
/// coordinate key so it can be a SQLite/Postgres primary key column
/// directly.
String cellKeyFor(double latitude, double longitude) {
  final x = longitude;
  final y = latitude;
  final qFrac = (2 / 3 * x) / _hexSizeDeg;
  final rFrac = (-1 / 3 * x + _sqrt3 / 3 * y) / _hexSizeDeg;
  final (q, r) = _roundAxial(qFrac, rFrac);
  return '$q:$r';
}

/// Rounds fractional axial coordinates to the nearest actual hex by
/// rounding in cube coordinates (x=q, z=r, y=-x-z) and fixing whichever
/// of the three ends up furthest from an integer — the standard
/// hex-rounding trick, since rounding q and r independently can land
/// you in the wrong hex near a shared edge.
(int, int) _roundAxial(double qFrac, double rFrac) {
  final cubeX = qFrac;
  final cubeZ = rFrac;
  final cubeY = -cubeX - cubeZ;
  var rx = cubeX.round();
  var ry = cubeY.round();
  var rz = cubeZ.round();
  final xDiff = (rx - cubeX).abs();
  final yDiff = (ry - cubeY).abs();
  final zDiff = (rz - cubeZ).abs();
  if (xDiff > yDiff && xDiff > zDiff) {
    rx = -ry - rz;
  } else if (yDiff > zDiff) {
    ry = -rx - rz;
  } else {
    rz = -rx - ry;
  }
  return (rx, rz);
}

/// Every distinct hex cell a trip's route passed through.
Set<String> cellsForTrip(Iterable<TripPoint> points) {
  return points.map((p) => cellKeyFor(p.latitude, p.longitude)).toSet();
}

LatLng _hexCenter(int q, int r) {
  final x = _hexSizeDeg * (3 / 2 * q);
  final y = _hexSizeDeg * (_sqrt3 / 2 * q + _sqrt3 * r);
  return LatLng(y, x);
}

/// The inverse of [cellKeyFor] — the hexagon a cell key covers, as its 6
/// corners in order, for drawing it on a map (see
/// gamification/territory_map_screen.dart).
List<LatLng> cellPolygonFor(String cellKey) {
  final parts = cellKey.split(':');
  final q = int.parse(parts[0]);
  final r = int.parse(parts[1]);
  final center = _hexCenter(q, r);
  return [
    for (var i = 0; i < 6; i++)
      LatLng(
        center.latitude + _hexSizeDeg * math.sin(_degToRad(60 * i)),
        center.longitude + _hexSizeDeg * math.cos(_degToRad(60 * i)),
      ),
  ];
}

double _degToRad(num deg) => deg * math.pi / 180;
