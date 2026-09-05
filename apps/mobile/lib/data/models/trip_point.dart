class TripPoint {
  final String tripId;
  final int seq;
  final double latitude;
  final double longitude;
  final double? altitudeMeters;
  final double? speedKph;
  final DateTime timestamp;

  // Vehicle-reported (BLE) telemetry at this exact GPS fix — populated
  // only while a Kawasaki Rideology-connected bike is connected during
  // recording (see trip/recording_screen.dart, which stamps these onto
  // each point as it comes off LocationRecorder.pointStream, using
  // whatever the latest telemetry frame happened to be at that moment;
  // LocationRecorder itself stays GPS-only and knows nothing about BLE).
  // Sampled at GPS-fix cadence rather than every BLE frame (which arrives
  // much faster) — plenty of resolution for a replay HUD, without
  // multiplying point-storage volume by the telemetry frame rate. This is
  // what lets trips/trip_detail_screen.dart's route replay show live
  // instrument readouts as the marker moves, not just an animated dot.
  final double? bleSpeedKph;
  final int? bleRpm;
  final int? bleGear;
  final double? bleThrottlePercent;
  final double? bleLeanDeg;
  final int? bleWaterTemperatureC;

  // The rest of what RidingTelemetry can carry — kept per-point (not just
  // as a trip-level max/min, see data/models/trip.dart) so the replay HUD
  // can show how each of these actually moved over the ride, not just its
  // extreme value.
  final double? bleAccelG;
  final double? bleFrontBrakePressureKpa;
  final int? bleTcsLevelHb;
  final int? bleTcsLevelLb;
  final double? bleBattery12V;
  final double? bleOdometerKm;
  final double? bleTripAKm;
  final double? bleTripBKm;
  final int? bleFuelGauge;
  final int? bleInletAirTemperatureC;
  final double? bleTirePressureFrKpa;
  final double? bleTirePressureRrKpa;

  const TripPoint({
    required this.tripId,
    required this.seq,
    required this.latitude,
    required this.longitude,
    this.altitudeMeters,
    this.speedKph,
    required this.timestamp,
    this.bleSpeedKph,
    this.bleRpm,
    this.bleGear,
    this.bleThrottlePercent,
    this.bleLeanDeg,
    this.bleWaterTemperatureC,
    this.bleAccelG,
    this.bleFrontBrakePressureKpa,
    this.bleTcsLevelHb,
    this.bleTcsLevelLb,
    this.bleBattery12V,
    this.bleOdometerKm,
    this.bleTripAKm,
    this.bleTripBKm,
    this.bleFuelGauge,
    this.bleInletAirTemperatureC,
    this.bleTirePressureFrKpa,
    this.bleTirePressureRrKpa,
  });

  /// Whether this point carries any bike telemetry at all — checked once
  /// by the replay HUD instead of testing every field individually.
  bool get hasBleTelemetry =>
      bleSpeedKph != null ||
      bleRpm != null ||
      bleGear != null ||
      bleThrottlePercent != null ||
      bleLeanDeg != null ||
      bleWaterTemperatureC != null ||
      bleAccelG != null ||
      bleFrontBrakePressureKpa != null ||
      bleTcsLevelHb != null ||
      bleTcsLevelLb != null ||
      bleBattery12V != null ||
      bleOdometerKm != null ||
      bleTripAKm != null ||
      bleTripBKm != null ||
      bleFuelGauge != null ||
      bleInletAirTemperatureC != null ||
      bleTirePressureFrKpa != null ||
      bleTirePressureRrKpa != null;

  TripPoint copyWith({
    double? bleSpeedKph,
    int? bleRpm,
    int? bleGear,
    double? bleThrottlePercent,
    double? bleLeanDeg,
    int? bleWaterTemperatureC,
    double? bleAccelG,
    double? bleFrontBrakePressureKpa,
    int? bleTcsLevelHb,
    int? bleTcsLevelLb,
    double? bleBattery12V,
    double? bleOdometerKm,
    double? bleTripAKm,
    double? bleTripBKm,
    int? bleFuelGauge,
    int? bleInletAirTemperatureC,
    double? bleTirePressureFrKpa,
    double? bleTirePressureRrKpa,
  }) {
    return TripPoint(
      tripId: tripId,
      seq: seq,
      latitude: latitude,
      longitude: longitude,
      altitudeMeters: altitudeMeters,
      speedKph: speedKph,
      timestamp: timestamp,
      bleSpeedKph: bleSpeedKph ?? this.bleSpeedKph,
      bleRpm: bleRpm ?? this.bleRpm,
      bleGear: bleGear ?? this.bleGear,
      bleThrottlePercent: bleThrottlePercent ?? this.bleThrottlePercent,
      bleLeanDeg: bleLeanDeg ?? this.bleLeanDeg,
      bleWaterTemperatureC: bleWaterTemperatureC ?? this.bleWaterTemperatureC,
      bleAccelG: bleAccelG ?? this.bleAccelG,
      bleFrontBrakePressureKpa: bleFrontBrakePressureKpa ?? this.bleFrontBrakePressureKpa,
      bleTcsLevelHb: bleTcsLevelHb ?? this.bleTcsLevelHb,
      bleTcsLevelLb: bleTcsLevelLb ?? this.bleTcsLevelLb,
      bleBattery12V: bleBattery12V ?? this.bleBattery12V,
      bleOdometerKm: bleOdometerKm ?? this.bleOdometerKm,
      bleTripAKm: bleTripAKm ?? this.bleTripAKm,
      bleTripBKm: bleTripBKm ?? this.bleTripBKm,
      bleFuelGauge: bleFuelGauge ?? this.bleFuelGauge,
      bleInletAirTemperatureC: bleInletAirTemperatureC ?? this.bleInletAirTemperatureC,
      bleTirePressureFrKpa: bleTirePressureFrKpa ?? this.bleTirePressureFrKpa,
      bleTirePressureRrKpa: bleTirePressureRrKpa ?? this.bleTirePressureRrKpa,
    );
  }

  Map<String, Object?> toRow() => {
    'trip_id': tripId,
    'seq': seq,
    'latitude': latitude,
    'longitude': longitude,
    'altitude_meters': altitudeMeters,
    'speed_kph': speedKph,
    'timestamp': timestamp.toIso8601String(),
    'ble_speed_kph': bleSpeedKph,
    'ble_rpm': bleRpm,
    'ble_gear': bleGear,
    'ble_throttle_percent': bleThrottlePercent,
    'ble_lean_deg': bleLeanDeg,
    'ble_water_temp_c': bleWaterTemperatureC,
    'ble_accel_g': bleAccelG,
    'ble_front_brake_kpa': bleFrontBrakePressureKpa,
    'ble_tcs_level_hb': bleTcsLevelHb,
    'ble_tcs_level_lb': bleTcsLevelLb,
    'ble_battery_12v': bleBattery12V,
    'ble_odometer_km': bleOdometerKm,
    'ble_trip_a_km': bleTripAKm,
    'ble_trip_b_km': bleTripBKm,
    'ble_fuel_gauge': bleFuelGauge,
    'ble_inlet_air_temp_c': bleInletAirTemperatureC,
    'ble_tire_pressure_fr_kpa': bleTirePressureFrKpa,
    'ble_tire_pressure_rr_kpa': bleTirePressureRrKpa,
  };

  static TripPoint fromRow(Map<String, Object?> row) => TripPoint(
    tripId: row['trip_id'] as String,
    seq: row['seq'] as int,
    latitude: row['latitude'] as double,
    longitude: row['longitude'] as double,
    altitudeMeters: row['altitude_meters'] as double?,
    speedKph: row['speed_kph'] as double?,
    timestamp: DateTime.parse(row['timestamp'] as String),
    bleSpeedKph: row['ble_speed_kph'] as double?,
    bleRpm: row['ble_rpm'] as int?,
    bleGear: row['ble_gear'] as int?,
    bleThrottlePercent: row['ble_throttle_percent'] as double?,
    bleLeanDeg: row['ble_lean_deg'] as double?,
    bleWaterTemperatureC: row['ble_water_temp_c'] as int?,
    bleAccelG: row['ble_accel_g'] as double?,
    bleFrontBrakePressureKpa: row['ble_front_brake_kpa'] as double?,
    bleTcsLevelHb: row['ble_tcs_level_hb'] as int?,
    bleTcsLevelLb: row['ble_tcs_level_lb'] as int?,
    bleBattery12V: row['ble_battery_12v'] as double?,
    bleOdometerKm: row['ble_odometer_km'] as double?,
    bleTripAKm: row['ble_trip_a_km'] as double?,
    bleTripBKm: row['ble_trip_b_km'] as double?,
    bleFuelGauge: row['ble_fuel_gauge'] as int?,
    bleInletAirTemperatureC: row['ble_inlet_air_temp_c'] as int?,
    bleTirePressureFrKpa: row['ble_tire_pressure_fr_kpa'] as double?,
    bleTirePressureRrKpa: row['ble_tire_pressure_rr_kpa'] as double?,
  );

  /// What gets pushed to Supabase (supabase/schema.sql's `trip_points`
  /// table) — identical shape to [toRow], but kept separate so the two
  /// schemas (local SQLite vs. remote Postgres) can drift independently
  /// without silently breaking the other, and so `"timestamp"` (a quoted
  /// reserved word in Postgres) reads as deliberate here, not a typo.
  Map<String, Object?> toSupabaseRow() => {
    'trip_id': tripId,
    'seq': seq,
    'latitude': latitude,
    'longitude': longitude,
    'altitude_meters': altitudeMeters,
    'speed_kph': speedKph,
    'timestamp': timestamp.toIso8601String(),
    'ble_speed_kph': bleSpeedKph,
    'ble_rpm': bleRpm,
    'ble_gear': bleGear,
    'ble_throttle_percent': bleThrottlePercent,
    'ble_lean_deg': bleLeanDeg,
    'ble_water_temp_c': bleWaterTemperatureC,
    'ble_accel_g': bleAccelG,
    'ble_front_brake_kpa': bleFrontBrakePressureKpa,
    'ble_tcs_level_hb': bleTcsLevelHb,
    'ble_tcs_level_lb': bleTcsLevelLb,
    'ble_battery_12v': bleBattery12V,
    'ble_odometer_km': bleOdometerKm,
    'ble_trip_a_km': bleTripAKm,
    'ble_trip_b_km': bleTripBKm,
    'ble_fuel_gauge': bleFuelGauge,
    'ble_inlet_air_temp_c': bleInletAirTemperatureC,
    'ble_tire_pressure_fr_kpa': bleTirePressureFrKpa,
    'ble_tire_pressure_rr_kpa': bleTirePressureRrKpa,
  };

  static TripPoint fromSupabaseRow(Map<String, Object?> row) => TripPoint(
    tripId: row['trip_id'] as String,
    seq: row['seq'] as int,
    latitude: (row['latitude'] as num).toDouble(),
    longitude: (row['longitude'] as num).toDouble(),
    altitudeMeters: (row['altitude_meters'] as num?)?.toDouble(),
    speedKph: (row['speed_kph'] as num?)?.toDouble(),
    timestamp: DateTime.parse(row['timestamp'] as String),
    bleSpeedKph: (row['ble_speed_kph'] as num?)?.toDouble(),
    bleRpm: row['ble_rpm'] as int?,
    bleGear: row['ble_gear'] as int?,
    bleThrottlePercent: (row['ble_throttle_percent'] as num?)?.toDouble(),
    bleLeanDeg: (row['ble_lean_deg'] as num?)?.toDouble(),
    bleWaterTemperatureC: row['ble_water_temp_c'] as int?,
    bleAccelG: (row['ble_accel_g'] as num?)?.toDouble(),
    bleFrontBrakePressureKpa: (row['ble_front_brake_kpa'] as num?)?.toDouble(),
    bleTcsLevelHb: row['ble_tcs_level_hb'] as int?,
    bleTcsLevelLb: row['ble_tcs_level_lb'] as int?,
    bleBattery12V: (row['ble_battery_12v'] as num?)?.toDouble(),
    bleOdometerKm: (row['ble_odometer_km'] as num?)?.toDouble(),
    bleTripAKm: (row['ble_trip_a_km'] as num?)?.toDouble(),
    bleTripBKm: (row['ble_trip_b_km'] as num?)?.toDouble(),
    bleFuelGauge: row['ble_fuel_gauge'] as int?,
    bleInletAirTemperatureC: row['ble_inlet_air_temp_c'] as int?,
    bleTirePressureFrKpa: (row['ble_tire_pressure_fr_kpa'] as num?)?.toDouble(),
    bleTirePressureRrKpa: (row['ble_tire_pressure_rr_kpa'] as num?)?.toDouble(),
  );
}
