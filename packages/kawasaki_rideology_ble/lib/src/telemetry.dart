/// A live, unit-converted snapshot of what the bike is doing right now.
/// Built up incrementally as different frame types arrive — frame 0x4A
/// (riding log mid) updates most fields most often; 0x41/0x45 fill in
/// odometer/trip/battery/temperature less frequently; 0x03 fills in the
/// VIN once at connect time.
///
/// Any field can be `null`, either because this bike doesn't support it
/// (see [BikeConfig.supportedFields]) or because that frame hasn't arrived
/// yet.
class RidingTelemetry {
  final DateTime timestamp;

  // From frame 0x4A (riding log mid) — the continuous live-telemetry frame.
  final int? rpm;
  final int? speedKph;
  final int? gear;
  final double? throttlePercent;
  final double? leanDeg;
  final double? accelG;
  final double? frontBrakePressureKpa;
  final int? tcsLevelHb;
  final int? tcsLevelLb;

  // From frame 0x41 (MC info).
  final double? ecuBattery12V;
  final int? odometerTenthKm;
  final double? tripAKm;
  final double? tripBKm;
  final int? fuelGauge;

  // From frame 0x45 (riding log ext).
  final int? waterTemperatureC;
  final int? inletAirTemperatureC;
  final double? tirePressureFrKpa;
  final double? tirePressureRrKpa;

  // From frame 0x03 (model info) — set once, doesn't change per-frame.
  final String? vin;
  final String? modelName;

  const RidingTelemetry({
    required this.timestamp,
    this.rpm,
    this.speedKph,
    this.gear,
    this.throttlePercent,
    this.leanDeg,
    this.accelG,
    this.frontBrakePressureKpa,
    this.tcsLevelHb,
    this.tcsLevelLb,
    this.ecuBattery12V,
    this.odometerTenthKm,
    this.tripAKm,
    this.tripBKm,
    this.fuelGauge,
    this.waterTemperatureC,
    this.inletAirTemperatureC,
    this.tirePressureFrKpa,
    this.tirePressureRrKpa,
    this.vin,
    this.modelName,
  });

  factory RidingTelemetry.empty() => RidingTelemetry(timestamp: DateTime.now());

  RidingTelemetry copyWith({
    DateTime? timestamp,
    int? rpm,
    int? speedKph,
    int? gear,
    double? throttlePercent,
    double? leanDeg,
    double? accelG,
    double? frontBrakePressureKpa,
    int? tcsLevelHb,
    int? tcsLevelLb,
    double? ecuBattery12V,
    int? odometerTenthKm,
    double? tripAKm,
    double? tripBKm,
    int? fuelGauge,
    int? waterTemperatureC,
    int? inletAirTemperatureC,
    double? tirePressureFrKpa,
    double? tirePressureRrKpa,
    String? vin,
    String? modelName,
  }) {
    return RidingTelemetry(
      timestamp: timestamp ?? this.timestamp,
      rpm: rpm ?? this.rpm,
      speedKph: speedKph ?? this.speedKph,
      gear: gear ?? this.gear,
      throttlePercent: throttlePercent ?? this.throttlePercent,
      leanDeg: leanDeg ?? this.leanDeg,
      accelG: accelG ?? this.accelG,
      frontBrakePressureKpa: frontBrakePressureKpa ?? this.frontBrakePressureKpa,
      tcsLevelHb: tcsLevelHb ?? this.tcsLevelHb,
      tcsLevelLb: tcsLevelLb ?? this.tcsLevelLb,
      ecuBattery12V: ecuBattery12V ?? this.ecuBattery12V,
      odometerTenthKm: odometerTenthKm ?? this.odometerTenthKm,
      tripAKm: tripAKm ?? this.tripAKm,
      tripBKm: tripBKm ?? this.tripBKm,
      fuelGauge: fuelGauge ?? this.fuelGauge,
      waterTemperatureC: waterTemperatureC ?? this.waterTemperatureC,
      inletAirTemperatureC: inletAirTemperatureC ?? this.inletAirTemperatureC,
      tirePressureFrKpa: tirePressureFrKpa ?? this.tirePressureFrKpa,
      tirePressureRrKpa: tirePressureRrKpa ?? this.tirePressureRrKpa,
      vin: vin ?? this.vin,
      modelName: modelName ?? this.modelName,
    );
  }
}
