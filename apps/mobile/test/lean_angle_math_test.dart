import 'package:flutter_test/flutter_test.dart';
import 'package:opentrip_mobile/trip/lean_angle_math.dart';

void main() {
  test('identical vectors are zero degrees apart', () {
    final angle = angleBetweenVectorsDeg(x1: 0, y1: 9.8, z1: 0, x2: 0, y2: 9.8, z2: 0);
    expect(angle, closeTo(0, 0.001));
  });

  test('perpendicular vectors are 90 degrees apart', () {
    final angle = angleBetweenVectorsDeg(x1: 9.8, y1: 0, z1: 0, x2: 0, y2: 9.8, z2: 0);
    expect(angle, closeTo(90, 0.001));
  });

  test('opposite vectors are 180 degrees apart', () {
    final angle = angleBetweenVectorsDeg(x1: 0, y1: 9.8, z1: 0, x2: 0, y2: -9.8, z2: 0);
    expect(angle, closeTo(180, 0.001));
  });

  test('a known 45-degree tilt', () {
    // Reference straight "up" on Y; tilted vector split evenly between X and Y.
    final angle = angleBetweenVectorsDeg(x1: 0, y1: 1, z1: 0, x2: 1, y2: 1, z2: 0);
    expect(angle, closeTo(45, 0.001));
  });

  test('differing magnitudes do not affect the angle', () {
    final angle = angleBetweenVectorsDeg(x1: 0, y1: 1, z1: 0, x2: 0, y2: 50, z2: 0);
    expect(angle, closeTo(0, 0.001));
  });

  test('a zero-length vector returns zero instead of dividing by zero', () {
    final angle = angleBetweenVectorsDeg(x1: 0, y1: 0, z1: 0, x2: 0, y2: 9.8, z2: 0);
    expect(angle, 0);
  });
}
