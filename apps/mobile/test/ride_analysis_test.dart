import 'package:flutter_test/flutter_test.dart';
import 'package:opentrip_mobile/data/models/trip_point.dart';
import 'package:opentrip_mobile/trip/ride_analysis.dart';

TripPoint _pt(int seq, {double? speed, double? phoneLean, double? bleLean, double lat = 0, double lon = 0}) =>
    TripPoint(
      tripId: 't',
      seq: seq,
      latitude: lat,
      longitude: lon,
      speedKph: speed,
      phoneLeanDeg: phoneLean,
      bleLeanDeg: bleLean,
      timestamp: DateTime(2026, 1, 1).add(Duration(seconds: seq)),
    );

void main() {
  group('effective readings', () {
    test('BLE lean wins over phone lean, and is unsigned', () {
      expect(effectiveLeanDeg(_pt(0, phoneLean: 10, bleLean: -32)), 32);
      expect(effectiveLeanDeg(_pt(0, phoneLean: 10)), 10);
      expect(effectiveLeanDeg(_pt(0)), isNull);
    });
  });

  group('segmentRoute', () {
    test('merges consecutive same-bucket points and shares boundary points', () {
      final points = [_pt(0, speed: 10), _pt(1, speed: 12), _pt(2, speed: 90), _pt(3, speed: 95)];
      final segments = segmentRoute(points, RideMetric.speed, scaleMax: 100, buckets: 4);
      expect(segments.length, 2);
      expect((segments[0].startIndex, segments[0].endIndex), (0, 2));
      expect((segments[1].startIndex, segments[1].endIndex), (2, 3));
      expect(segments[0].level, lessThan(segments[1].level!));
    });

    test('points with no reading get a null level', () {
      final points = [_pt(0), _pt(1), _pt(2, phoneLean: 20)];
      final segments = segmentRoute(points, RideMetric.lean, scaleMax: 40);
      expect(segments.first.level, isNull);
    });

    test('fewer than two points draws nothing', () {
      expect(segmentRoute([_pt(0, speed: 5)], RideMetric.speed, scaleMax: 30), isEmpty);
    });
  });

  test('scaleMaxFor floors a slow ride so tiny values are not stretched', () {
    expect(scaleMaxFor([_pt(0, speed: 3)], RideMetric.speed), 30);
    expect(scaleMaxFor([_pt(0, speed: 140)], RideMetric.speed), 140);
  });

  group('detectCorners', () {
    test('finds separate corners, deepest first, with apex speed', () {
      final points = [
        _pt(0, phoneLean: 2, speed: 80),
        _pt(1, phoneLean: 20, speed: 60),
        _pt(2, phoneLean: 28, speed: 55),
        _pt(3, phoneLean: 18, speed: 58),
        _pt(4, phoneLean: 3, speed: 70),
        _pt(5, phoneLean: 4, speed: 75),
        _pt(6, phoneLean: 35, speed: 50),
        _pt(7, phoneLean: 5, speed: 60),
        _pt(8, phoneLean: 2, speed: 60),
      ];
      final corners = detectCorners(points);
      expect(corners.length, 2);
      expect(corners[0].peakLeanDeg, 35);
      expect(corners[0].apexSpeedKph, 50);
      expect(corners[1].peakIndex, 2);
      expect((corners[1].startIndex, corners[1].endIndex), (1, 3));
    });

    test('a single noisy dip mid-corner does not split it', () {
      final points = [
        _pt(0, phoneLean: 20),
        _pt(1, phoneLean: 10),
        _pt(2, phoneLean: 25),
        _pt(3, phoneLean: 0),
        _pt(4, phoneLean: 0)
      ];
      expect(detectCorners(points).length, 1);
    });

    test('no lean data means no corners', () {
      expect(detectCorners([_pt(0, speed: 50), _pt(1, speed: 60)]), isEmpty);
    });
  });

  test('nearestPointIndex ignores taps far off the route', () {
    final points = [_pt(0, lat: 0, lon: 0), _pt(1, lat: 0, lon: 0.001)];
    expect(nearestPointIndex(points, 0, 0.0009), 1);
    expect(nearestPointIndex(points, 1, 1), isNull);
  });
}
