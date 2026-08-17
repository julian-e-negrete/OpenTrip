import 'package:flutter_test/flutter_test.dart';
import 'package:opentrip_mobile/trip/driving_math.dart';

void main() {
  group('longitudinalAccelMps2', () {
    test('accelerating from a stop is positive', () {
      final accel = longitudinalAccelMps2(speedBeforeKph: 0, speedAfterKph: 36, dtSeconds: 4);
      // 36 kph = 10 m/s over 4s -> 2.5 m/s^2
      expect(accel, closeTo(2.5, 0.001));
    });

    test('braking is negative', () {
      final accel = longitudinalAccelMps2(speedBeforeKph: 72, speedAfterKph: 36, dtSeconds: 2);
      // -36 kph = -10 m/s over 2s -> -5 m/s^2
      expect(accel, closeTo(-5.0, 0.001));
    });

    test('zero elapsed time returns zero rather than dividing by zero', () {
      expect(longitudinalAccelMps2(speedBeforeKph: 0, speedAfterKph: 50, dtSeconds: 0), 0);
    });
  });

  group('headingDeltaDeg', () {
    test('straightforward difference within range', () {
      expect(headingDeltaDeg(10, 40), closeTo(30, 0.001));
    });

    test('wraps around 0/360 the short way', () {
      expect(headingDeltaDeg(350, 10), closeTo(20, 0.001));
      expect(headingDeltaDeg(10, 350), closeTo(-20, 0.001));
    });
  });

  group('lateralAccelMps2', () {
    test('a tight turn at speed produces a large lateral acceleration', () {
      final accel = lateralAccelMps2(headingBeforeDeg: 0, headingAfterDeg: 90, avgSpeedKph: 36, dtSeconds: 2);
      expect(accel, greaterThan(5.0));
    });

    test('driving straight produces zero lateral acceleration', () {
      final accel = lateralAccelMps2(headingBeforeDeg: 45, headingAfterDeg: 45, avgSpeedKph: 60, dtSeconds: 1);
      expect(accel, 0);
    });

    test('turning while stationary contributes nothing', () {
      final accel = lateralAccelMps2(headingBeforeDeg: 0, headingAfterDeg: 180, avgSpeedKph: 0, dtSeconds: 1);
      expect(accel, 0);
    });
  });

  test('mps2ToG converts standard gravity to 1.0', () {
    expect(mps2ToG(9.80665), closeTo(1.0, 0.0001));
  });
}
