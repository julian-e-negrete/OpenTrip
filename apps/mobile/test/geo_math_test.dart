import 'package:flutter_test/flutter_test.dart';
import 'package:opentrip_mobile/trip/geo_math.dart';

void main() {
  test('same point is zero distance', () {
    final d = haversineMeters(lat1: 40.0, lon1: -3.0, lat2: 40.0, lon2: -3.0);
    expect(d, closeTo(0, 1e-6));
  });

  test('one degree of latitude is roughly 111km', () {
    final d = haversineMeters(lat1: 0, lon1: 0, lat2: 1, lon2: 0);
    expect(d, closeTo(111195, 500));
  });

  test('known distance: Madrid to Barcelona is roughly 505km', () {
    // Puerta del Sol, Madrid -> Plaça de Catalunya, Barcelona.
    final d = haversineMeters(lat1: 40.4169, lon1: -3.7035, lat2: 41.3874, lon2: 2.1686);
    expect(d / 1000, closeTo(505, 10));
  });
}
