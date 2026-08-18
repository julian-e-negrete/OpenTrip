import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:opentrip_mobile/data/models/trip_point.dart';
import 'package:opentrip_mobile/gamification/territory.dart';

TripPoint _pt(double lat, double lng) => TripPoint(
  tripId: 't',
  seq: 0,
  latitude: lat,
  longitude: lng,
  timestamp: DateTime(2026),
);

/// Standard ray-casting point-in-polygon test, used below to check that
/// [cellPolygonFor] actually covers the point that produced its key.
bool _polygonContains(List<LatLng> polygon, LatLng point) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final xi = polygon[i].longitude, yi = polygon[i].latitude;
    final xj = polygon[j].longitude, yj = polygon[j].latitude;
    final intersects =
        ((yi > point.latitude) != (yj > point.latitude)) &&
        (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi);
    if (intersects) inside = !inside;
  }
  return inside;
}

void main() {
  test('nearby points within the same hex share a key', () {
    expect(cellKeyFor(40.4168, -3.7038), cellKeyFor(40.4169, -3.7039));
  });

  test('points several hex widths apart get different keys', () {
    expect(cellKeyFor(40.40, -3.70), isNot(cellKeyFor(40.42, -3.70)));
  });

  test('cellsForTrip deduplicates revisited cells', () {
    final cells = cellsForTrip([
      _pt(40.4168, -3.7038),
      _pt(40.4168, -3.7038), // exact revisit
      _pt(40.4169, -3.7039), // same cell, tiny jitter
      _pt(41.0, -3.7038), // a genuinely different cell
    ]);
    expect(cells.length, 2);
  });

  test('cellPolygonFor contains the point that produced its key', () {
    const lat = 40.4168;
    const lng = -3.7038;
    final polygon = cellPolygonFor(cellKeyFor(lat, lng));
    expect(polygon.length, 6);
    expect(_polygonContains(polygon, const LatLng(lat, lng)), isTrue);
  });

  test('cellPolygonFor handles negative axial coordinates without a sign clash', () {
    // Both q and r land negative here — makes sure splitting the "q:r"
    // key on ':' doesn't get confused by the leading '-' on each half.
    const lat = -33.865;
    const lng = -70.65;
    final polygon = cellPolygonFor(cellKeyFor(lat, lng));
    expect(_polygonContains(polygon, const LatLng(lat, lng)), isTrue);
  });
}
