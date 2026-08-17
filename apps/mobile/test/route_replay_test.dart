import 'package:flutter_test/flutter_test.dart';
import 'package:opentrip_mobile/data/models/trip_point.dart';
import 'package:opentrip_mobile/trip/route_replay.dart';

TripPoint _pt(double lat, double lon, int secondsOffset) => TripPoint(
  tripId: 't',
  seq: secondsOffset,
  latitude: lat,
  longitude: lon,
  timestamp: DateTime(2026, 1, 1).add(Duration(seconds: secondsOffset)),
);

void main() {
  group('positionAtProgress', () {
    test('progress 0 is the first point, progress 1 is the last', () {
      final points = [_pt(0, 0, 0), _pt(1, 1, 10)];
      expect(positionAtProgress(points, 0), (0.0, 0.0));
      expect(positionAtProgress(points, 1), (1.0, 1.0));
    });

    test('interpolates the midpoint at 50% elapsed time', () {
      final points = [_pt(0, 0, 0), _pt(2, 4, 10)];
      final (lat, lon) = positionAtProgress(points, 0.5);
      expect(lat, closeTo(1.0, 0.001));
      expect(lon, closeTo(2.0, 0.001));
    });

    test('paces by real elapsed time, not point index — a stop bunches points', () {
      // Idles at (0,0) through t=3s (four bunched points, one per
      // second), then a single fast final leg to (10,10) at t=6s. Total
      // duration is 6s, so 50% elapsed time is t=3s — right at the end
      // of the idle cluster, not halfway through the 5-entry point list
      // (which index-based pacing would put mid-leg, already moving).
      final points = [
        _pt(0, 0, 0),
        _pt(0, 0, 1),
        _pt(0, 0, 2),
        _pt(0, 0, 3),
        _pt(10, 10, 6),
      ];
      final (lat, lon) = positionAtProgress(points, 0.5); // t=3s, still idling
      expect(lat, closeTo(0.0, 0.001));
      expect(lon, closeTo(0.0, 0.001));
    });

    test('a single point returns itself regardless of progress', () {
      final points = [_pt(5, 6, 0)];
      expect(positionAtProgress(points, 0.7), (5.0, 6.0));
    });

    test('an empty list returns the origin without throwing', () {
      expect(positionAtProgress(const [], 0.5), (0.0, 0.0));
    });
  });

  group('pointCountAtProgress', () {
    test('progress 0 includes just the first point', () {
      final points = [_pt(0, 0, 0), _pt(1, 1, 5), _pt(2, 2, 10)];
      expect(pointCountAtProgress(points, 0), 1);
    });

    test('progress 1 includes every point', () {
      final points = [_pt(0, 0, 0), _pt(1, 1, 5), _pt(2, 2, 10)];
      expect(pointCountAtProgress(points, 1), 3);
    });

    test('midway includes only points reached by that elapsed time', () {
      final points = [_pt(0, 0, 0), _pt(1, 1, 5), _pt(2, 2, 10)];
      expect(pointCountAtProgress(points, 0.4), 1); // t=4s, hasn't reached the t=5s point yet
      expect(pointCountAtProgress(points, 0.6), 2); // t=6s, past the t=5s point
    });
  });
}
