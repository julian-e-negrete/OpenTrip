import 'dart:math' as math;

/// Pure math behind trip/location_recorder.dart's driving-behavior stats
/// (acceleration, braking, cornering) — deliberately derived entirely
/// from the GPS stream (speed + course-over-ground) already flowing
/// through the recorder, not a raw accelerometer/gyroscope reading.
///
/// A phone's accelerometer reports in the *phone's own* reference frame
/// — mounted upright on a dash, flat in a cupholder, in a pocket, its
/// x/y/z axes point in completely different real-world directions each
/// time, and telling "that jolt was braking" from "that jolt was a hard
/// right turn" needs knowing the phone's orientation relative to the
/// vehicle, which needs its own calibration step this project doesn't
/// have. Reporting confident-looking "3 hard brakes, 2 hard corners"
/// numbers built on data that can't actually tell those apart would be
/// worse than not having the feature. GPS course-over-ground, by
/// contrast, is already in a real-world (compass) reference frame
/// regardless of how the phone is oriented — trading a little precision
/// (GPS noise, not a real IMU) for numbers that are honestly what they
/// claim to be.

/// Longitudinal acceleration in m/s², from the change in GPS speed over
/// time — positive is accelerating, negative is braking.
double longitudinalAccelMps2({
  required double speedBeforeKph,
  required double speedAfterKph,
  required double dtSeconds,
}) {
  if (dtSeconds <= 0) return 0;
  final deltaMetersPerSecond = (speedAfterKph - speedBeforeKph) / 3.6;
  return deltaMetersPerSecond / dtSeconds;
}

/// The signed shortest angular difference from [fromDeg] to [toDeg], in
/// degrees, correctly handling the 0°/360° wraparound (e.g. 350° to 10°
/// is +20°, not -340°).
double headingDeltaDeg(double fromDeg, double toDeg) {
  var delta = (toDeg - fromDeg) % 360;
  if (delta > 180) delta -= 360;
  if (delta < -180) delta += 360;
  return delta;
}

/// Centripetal (cornering) acceleration magnitude in m/s², estimated as
/// v · dθ/dt from how fast GPS course-over-ground is turning while
/// moving at [avgSpeedKph]. Course-over-ground is unreliable near zero
/// speed (see geolocator's `Position.heading` doc comment), so callers
/// should only use this above a sane minimum speed —
/// trip/location_recorder.dart gates it at 8 km/h.
double lateralAccelMps2({
  required double headingBeforeDeg,
  required double headingAfterDeg,
  required double avgSpeedKph,
  required double dtSeconds,
}) {
  if (dtSeconds <= 0) return 0;
  final deltaRad = headingDeltaDeg(headingBeforeDeg, headingAfterDeg) * (math.pi / 180.0);
  final avgSpeedMetersPerSecond = avgSpeedKph / 3.6;
  return (avgSpeedMetersPerSecond * deltaRad / dtSeconds).abs();
}

const _metersPerSecondSquaredPerG = 9.80665;

double mps2ToG(double mps2) => mps2 / _metersPerSecondSquaredPerG;
