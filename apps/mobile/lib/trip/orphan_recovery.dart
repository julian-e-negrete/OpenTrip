import 'dart:async';

import '../data/models/trip.dart';
import '../data/models/trip_point.dart';
import '../data/repositories/trip_repository.dart';
import '../gamification/gamification_service.dart';
import 'accel_run_tracker.dart';
import 'driving_math.dart';
import 'geo_math.dart';

/// Recovers a trip whose recording session died before Stop & Save ever
/// ran (app crash, OS kill, phone restart) — see trips/trip_history_screen.dart's
/// delete-guard for how this class of trip is identified (unfinished,
/// but no live recording behind it in this app session). Its GPS points
/// were already saved as they came in (trip/location_recorder.dart
/// flushes points periodically, not just at the end), so the ride isn't
/// actually lost — only the final summary/finish step is missing.
///
/// Recomputes distance/duration/avg/max speed, BLE telemetry min/max,
/// GPS-derived acceleration/braking, and roll-race checkpoints by
/// replaying the same pure math this app already uses live
/// (trip/driving_math.dart, trip/accel_run_tracker.dart) over the
/// stored point sequence instead of a live stream — genuinely the same
/// numbers a normal Stop & Save would have produced, not an
/// approximation.
///
/// One real gap, disclosed rather than faked: cornering detection needs
/// GPS course-over-ground (heading) between consecutive fixes, and
/// heading was never persisted per-point (data/models/trip_point.dart
/// only stores speed, not heading) — only relevant live, where
/// trip/location_recorder.dart has it transiently. Recovered trips are
/// missing behaviorMaxCorneringG/behaviorHardCorneringCount as a result.
/// Phone-lean-angle (opt-in, accelerometer-derived) is similarly
/// unrecoverable — it was only ever tracked as a live running max, never
/// persisted per-point.
class OrphanRecovery {
  OrphanRecovery._();

  static const _hardAccelThresholdMps2 = 3.5;
  static const _hardBrakeThresholdMps2 = 4.0;

  /// Throws [StateError] if the trip has no saved points to recover from
  /// (nothing was ever accepted before the session died).
  static Future<Trip> recover({required String userId, required Trip trip}) async {
    final points = await TripRepository.instance.pointsForTrip(trip.id);
    if (points.isEmpty) {
      throw StateError('No GPS points were ever saved for this trip — there\'s nothing to recover.');
    }
    final sorted = [...points]..sort((a, b) => a.seq.compareTo(b.seq));

    double distanceMeters = 0;
    double? maxSpeedKph;
    double? maxAccelMps2;
    double? maxBrakeMps2;
    int hardAccelCount = 0;
    int hardBrakeCount = 0;
    final rollRace = RollRaceTracker();

    double? bleMaxSpeedKph;
    int? bleMaxRpm;
    double? bleMaxLeanDeg;
    double? bleMaxBrakeKpa;
    int? bleMinWaterTemp;
    int? bleMaxWaterTemp;
    double? bleMaxThrottle;
    double? bleMaxAccelG;
    int? bleMaxTcsLevel;
    double? bleMinBattery12V;
    double? bleMaxBattery12V;
    int? bleMinFuelGauge;
    int? bleMaxFuelGauge;
    int? bleMinInletAirTemp;
    int? bleMaxInletAirTemp;
    double? bleMinTirePressureFr;
    double? bleMaxTirePressureFr;
    double? bleMinTirePressureRr;
    double? bleMaxTirePressureRr;
    double? bleOdometerKm;
    double? bleTripAKm;
    double? bleTripBKm;

    TripPoint? last;
    for (final point in sorted) {
      final speedKph = point.speedKph;
      if (speedKph != null && (maxSpeedKph == null || speedKph > maxSpeedKph)) maxSpeedKph = speedKph;
      if (speedKph != null) rollRace.onFix(speedKph, point.timestamp);

      if (last != null) {
        distanceMeters += haversineMeters(
          lat1: last.latitude,
          lon1: last.longitude,
          lat2: point.latitude,
          lon2: point.longitude,
        );
        final dtSeconds = point.timestamp.difference(last.timestamp).inMilliseconds / 1000.0;
        if (dtSeconds > 0 && speedKph != null && last.speedKph != null) {
          final longAccel = longitudinalAccelMps2(
            speedBeforeKph: last.speedKph!,
            speedAfterKph: speedKph,
            dtSeconds: dtSeconds,
          );
          if (longAccel > _hardAccelThresholdMps2) {
            hardAccelCount++;
            if (maxAccelMps2 == null || longAccel > maxAccelMps2) maxAccelMps2 = longAccel;
          } else if (longAccel < -_hardBrakeThresholdMps2) {
            hardBrakeCount++;
            final magnitude = longAccel.abs();
            if (maxBrakeMps2 == null || magnitude > maxBrakeMps2) maxBrakeMps2 = magnitude;
          }
        }
      }
      last = point;

      final ble = point.bleSpeedKph;
      if (ble != null && (bleMaxSpeedKph == null || ble > bleMaxSpeedKph)) bleMaxSpeedKph = ble;
      if (point.bleRpm != null && (bleMaxRpm == null || point.bleRpm! > bleMaxRpm)) bleMaxRpm = point.bleRpm;
      if (point.bleLeanDeg != null) {
        final absLean = point.bleLeanDeg!.abs();
        if (bleMaxLeanDeg == null || absLean > bleMaxLeanDeg) bleMaxLeanDeg = absLean;
      }
      if (point.bleFrontBrakePressureKpa != null &&
          (bleMaxBrakeKpa == null || point.bleFrontBrakePressureKpa! > bleMaxBrakeKpa)) {
        bleMaxBrakeKpa = point.bleFrontBrakePressureKpa;
      }
      if (point.bleWaterTemperatureC != null) {
        if (bleMinWaterTemp == null || point.bleWaterTemperatureC! < bleMinWaterTemp) {
          bleMinWaterTemp = point.bleWaterTemperatureC;
        }
        if (bleMaxWaterTemp == null || point.bleWaterTemperatureC! > bleMaxWaterTemp) {
          bleMaxWaterTemp = point.bleWaterTemperatureC;
        }
      }
      if (point.bleThrottlePercent != null &&
          (bleMaxThrottle == null || point.bleThrottlePercent! > bleMaxThrottle)) {
        bleMaxThrottle = point.bleThrottlePercent;
      }
      if (point.bleAccelG != null) {
        final absAccel = point.bleAccelG!.abs();
        if (bleMaxAccelG == null || absAccel > bleMaxAccelG) bleMaxAccelG = absAccel;
      }
      final tcsLevel = [point.bleTcsLevelHb, point.bleTcsLevelLb].whereType<int>().fold<int?>(
        null,
        (max, v) => max == null || v > max ? v : max,
      );
      if (tcsLevel != null && (bleMaxTcsLevel == null || tcsLevel > bleMaxTcsLevel)) bleMaxTcsLevel = tcsLevel;
      if (point.bleBattery12V != null) {
        if (bleMinBattery12V == null || point.bleBattery12V! < bleMinBattery12V) bleMinBattery12V = point.bleBattery12V;
        if (bleMaxBattery12V == null || point.bleBattery12V! > bleMaxBattery12V) bleMaxBattery12V = point.bleBattery12V;
      }
      if (point.bleFuelGauge != null) {
        if (bleMinFuelGauge == null || point.bleFuelGauge! < bleMinFuelGauge) bleMinFuelGauge = point.bleFuelGauge;
        if (bleMaxFuelGauge == null || point.bleFuelGauge! > bleMaxFuelGauge) bleMaxFuelGauge = point.bleFuelGauge;
      }
      if (point.bleInletAirTemperatureC != null) {
        if (bleMinInletAirTemp == null || point.bleInletAirTemperatureC! < bleMinInletAirTemp) {
          bleMinInletAirTemp = point.bleInletAirTemperatureC;
        }
        if (bleMaxInletAirTemp == null || point.bleInletAirTemperatureC! > bleMaxInletAirTemp) {
          bleMaxInletAirTemp = point.bleInletAirTemperatureC;
        }
      }
      if (point.bleTirePressureFrKpa != null) {
        if (bleMinTirePressureFr == null || point.bleTirePressureFrKpa! < bleMinTirePressureFr) {
          bleMinTirePressureFr = point.bleTirePressureFrKpa;
        }
        if (bleMaxTirePressureFr == null || point.bleTirePressureFrKpa! > bleMaxTirePressureFr) {
          bleMaxTirePressureFr = point.bleTirePressureFrKpa;
        }
      }
      if (point.bleTirePressureRrKpa != null) {
        if (bleMinTirePressureRr == null || point.bleTirePressureRrKpa! < bleMinTirePressureRr) {
          bleMinTirePressureRr = point.bleTirePressureRrKpa;
        }
        if (bleMaxTirePressureRr == null || point.bleTirePressureRrKpa! > bleMaxTirePressureRr) {
          bleMaxTirePressureRr = point.bleTirePressureRrKpa;
        }
      }
      if (point.bleOdometerKm != null) bleOdometerKm = point.bleOdometerKm;
      if (point.bleTripAKm != null) bleTripAKm = point.bleTripAKm;
      if (point.bleTripBKm != null) bleTripBKm = point.bleTripBKm;
    }

    // The last accepted fix is the most honest available "when this
    // stopped" signal — the recording almost certainly kept running a
    // while longer before the process actually died, but nothing after
    // the last saved point is known, so there's nothing truthful to
    // extend it with.
    final endedAt = sorted.last.timestamp;
    final durationSeconds = endedAt.difference(sorted.first.timestamp).inSeconds;
    final avgSpeedKph = durationSeconds <= 0 ? null : (distanceMeters / 1000.0) / (durationSeconds / 3600.0);

    final recovered = trip.finish(
      endedAt: endedAt,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      avgSpeedKph: avgSpeedKph,
      maxSpeedKph: maxSpeedKph,
      pointCount: sorted.length,
      bleMaxSpeedKph: bleMaxSpeedKph,
      bleMaxRpm: bleMaxRpm,
      bleMaxLeanDeg: bleMaxLeanDeg,
      bleMaxBrakePressureKpa: bleMaxBrakeKpa,
      bleMinWaterTemperatureC: bleMinWaterTemp,
      bleMaxWaterTemperatureC: bleMaxWaterTemp,
      bleMaxThrottlePercent: bleMaxThrottle,
      bleMaxAccelG: bleMaxAccelG,
      bleMaxTcsLevel: bleMaxTcsLevel,
      bleMinBattery12V: bleMinBattery12V,
      bleMaxBattery12V: bleMaxBattery12V,
      bleMinFuelGauge: bleMinFuelGauge,
      bleMaxFuelGauge: bleMaxFuelGauge,
      bleMinInletAirTemperatureC: bleMinInletAirTemp,
      bleMaxInletAirTemperatureC: bleMaxInletAirTemp,
      bleMinTirePressureFrKpa: bleMinTirePressureFr,
      bleMaxTirePressureFrKpa: bleMaxTirePressureFr,
      bleMinTirePressureRrKpa: bleMinTirePressureRr,
      bleMaxTirePressureRrKpa: bleMaxTirePressureRr,
      bleTripAKm: bleTripAKm,
      bleTripBKm: bleTripBKm,
      bleOdometerKm: bleOdometerKm,
      behaviorMaxAccelG: maxAccelMps2 == null ? null : mps2ToG(maxAccelMps2),
      behaviorMaxBrakeG: maxBrakeMps2 == null ? null : mps2ToG(maxBrakeMps2),
      behaviorHardAccelCount: hardAccelCount,
      behaviorHardBrakeCount: hardBrakeCount,
      // Cornering isn't recoverable — see class doc.
      best0To60Seconds: rollRace.bestZeroToSixtySeconds,
      best0To180Seconds: rollRace.bestZeroToOneEightySeconds,
    );
    await TripRepository.instance.finishTrip(recovered);

    // Same gamification pass a normal Stop & Save triggers — the rider
    // genuinely covered this ground and earned whatever trophies apply,
    // even though the app crashed before it could say so at the time.
    unawaited(GamificationService.processFinishedTrip(userId: userId, trip: recovered, points: sorted));

    return recovered;
  }
}
