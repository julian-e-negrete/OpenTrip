import 'package:flutter_test/flutter_test.dart';
import 'package:opentrip_mobile/data/models/trip_point.dart';
import 'package:opentrip_mobile/gamification/territory.dart';

TripPoint _pt(double lat, double lng) => TripPoint(
  tripId: 't',
  seq: 0,
  latitude: lat,
  longitude: lng,
  timestamp: DateTime(2026),
);

void main() {
  test('nearby points within the same cell share a key', () {
    expect(cellKeyFor(40.4168, -3.7038), cellKeyFor(40.4169, -3.7039));
  });

  test('points a full cell width apart get different keys', () {
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
}
