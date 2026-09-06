class Trip {
  final String id;
  final String userId;
  final String vehicleId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double distanceMeters;
  final int durationSeconds;
  final double? avgSpeedKph;
  final double? maxSpeedKph;
  final int pointCount;

  // Vehicle-reported (BLE) telemetry summary, only populated if the
  // vehicle was connected via a live connector (see
  // vehicle/kawasaki_connector.dart) during recording. Null on a
  // GPS-only trip or on any vehicle without a connector. These are
  // separate from maxSpeedKph/avgSpeedKph above (which are always
  // GPS-derived) because the bike's own speedometer/tachometer reading is
  // more accurate than a GPS speed estimate, especially at low speed.
  final double? bleMaxSpeedKph;
  final int? bleMaxRpm;
  final double? bleMaxLeanDeg;
  final double? bleMaxBrakePressureKpa;
  final int? bleMinWaterTemperatureC;
  final int? bleMaxWaterTemperatureC;

  // The rest of what RidingTelemetry can report, summarized the same way
  // as the fields above — see trips/trip_detail_screen.dart's "Full bike
  // telemetry" section. Per-point values for all of these (so a replay
  // can show how they moved, not just their extreme) live on
  // data/models/trip_point.dart instead.
  final double? bleMaxThrottlePercent;
  final double? bleMaxAccelG;
  /// Highest traction-control intervention level seen (max of the
  /// protocol's high/low-byte TCS level fields) — not a temperature or
  /// pressure, just an activation-level indicator, so there's no
  /// meaningful "min" to pair it with the way water temp has one.
  final int? bleMaxTcsLevel;
  final double? bleMinBattery12V;
  final double? bleMaxBattery12V;
  final int? bleMinFuelGauge;
  final int? bleMaxFuelGauge;
  final int? bleMinInletAirTemperatureC;
  final int? bleMaxInletAirTemperatureC;
  final double? bleMinTirePressureFrKpa;
  final double? bleMaxTirePressureFrKpa;
  final double? bleMinTirePressureRrKpa;
  final double? bleMaxTirePressureRrKpa;

  /// The bike's own trip A/B odometer readings (Kawasaki Rideology's 0x41
  /// "MC info" frame) at the last telemetry frame received during this
  /// trip — last-write-wins like [bleOdometerKm] below, not a max/min.
  final double? bleTripAKm;
  final double? bleTripBKm;

  /// The bike's own odometer reading (Kawasaki Rideology's 0x41 "MC info"
  /// frame, `RidingTelemetry.odometerTenthKm`) at the last telemetry frame
  /// received during this trip — not a max/min like the fields above,
  /// just the latest reading, since a real odometer only ever counts up.
  /// This is what vehicles/vehicle_detail_screen.dart prefers for a
  /// vehicle's current mileage whenever it's available, over the
  /// app-tracked distance sum, since it's the bike's own hardware count
  /// rather than an estimate built from however much of the vehicle's
  /// life has been ridden with this app installed.
  final double? bleOdometerKm;

  // GPS-derived driving-behavior stats (trip/driving_math.dart) —
  // available for every trip regardless of vehicle, unlike the BLE
  // fields above. See that file's doc comment for why these come from
  // GPS speed/course-over-ground rather than the phone's accelerometer.
  // Null only if the trip had too few accepted GPS fixes to compute
  // them from (e.g. it ended almost immediately).
  final double? behaviorMaxAccelG;
  final double? behaviorMaxBrakeG;
  final double? behaviorMaxCorneringG;
  final int? behaviorHardAccelCount;
  final int? behaviorHardBrakeCount;
  final int? behaviorHardCorneringCount;

  /// Roll-race-style acceleration times (trip/accel_run_tracker.dart),
  /// GPS-derived like the behavior stats above — the best (lowest) time
  /// this trip crossed 0→60 km/h or 100→180 km/h, whether from a dedicated
  /// racing/ attempt or nailed incidentally on an ordinary ride. Null if
  /// the trip never crossed that bracket.
  final double? best0To60Seconds;
  final double? best100To180Seconds;

  /// Phone-accelerometer-derived max lean angle (trip/lean_angle_tracker.dart)
  /// — opt-in per recording (the "Track lean angle" toggle on
  /// trip/recording_screen.dart), unlike the GPS-derived behavior fields
  /// above, since it only means anything if the phone was actually
  /// mounted to the bike. Independent of [bleMaxLeanDeg] — a
  /// BLE-connected bike can have both, from two different sensors, and
  /// they won't necessarily agree.
  final double? phoneLeanMaxDeg;

  /// Whether this trip (and its points) has been pushed to Supabase. See
  /// sync/sync_service.dart. Always true for a trip that came from a pull.
  final bool synced;

  const Trip({
    required this.id,
    required this.userId,
    required this.vehicleId,
    required this.startedAt,
    this.endedAt,
    this.distanceMeters = 0,
    this.durationSeconds = 0,
    this.avgSpeedKph,
    this.maxSpeedKph,
    this.pointCount = 0,
    this.bleMaxSpeedKph,
    this.bleMaxRpm,
    this.bleMaxLeanDeg,
    this.bleMaxBrakePressureKpa,
    this.bleMinWaterTemperatureC,
    this.bleMaxWaterTemperatureC,
    this.bleMaxThrottlePercent,
    this.bleMaxAccelG,
    this.bleMaxTcsLevel,
    this.bleMinBattery12V,
    this.bleMaxBattery12V,
    this.bleMinFuelGauge,
    this.bleMaxFuelGauge,
    this.bleMinInletAirTemperatureC,
    this.bleMaxInletAirTemperatureC,
    this.bleMinTirePressureFrKpa,
    this.bleMaxTirePressureFrKpa,
    this.bleMinTirePressureRrKpa,
    this.bleMaxTirePressureRrKpa,
    this.bleTripAKm,
    this.bleTripBKm,
    this.bleOdometerKm,
    this.behaviorMaxAccelG,
    this.behaviorMaxBrakeG,
    this.behaviorMaxCorneringG,
    this.behaviorHardAccelCount,
    this.behaviorHardBrakeCount,
    this.behaviorHardCorneringCount,
    this.best0To60Seconds,
    this.best100To180Seconds,
    this.phoneLeanMaxDeg,
    this.synced = false,
  });

  bool get hasBleTelemetry => bleMaxSpeedKph != null || bleMaxRpm != null;

  bool get hasBehaviorStats =>
      behaviorMaxAccelG != null ||
      behaviorMaxBrakeG != null ||
      behaviorMaxCorneringG != null ||
      phoneLeanMaxDeg != null;

  bool get hasAccelStats => best0To60Seconds != null || best100To180Seconds != null;

  bool get isFinished => endedAt != null;

  double get distanceKm => distanceMeters / 1000.0;

  Trip finish({
    required DateTime endedAt,
    required double distanceMeters,
    required int durationSeconds,
    required double? avgSpeedKph,
    required double? maxSpeedKph,
    required int pointCount,
    double? bleMaxSpeedKph,
    int? bleMaxRpm,
    double? bleMaxLeanDeg,
    double? bleMaxBrakePressureKpa,
    int? bleMinWaterTemperatureC,
    int? bleMaxWaterTemperatureC,
    double? bleMaxThrottlePercent,
    double? bleMaxAccelG,
    int? bleMaxTcsLevel,
    double? bleMinBattery12V,
    double? bleMaxBattery12V,
    int? bleMinFuelGauge,
    int? bleMaxFuelGauge,
    int? bleMinInletAirTemperatureC,
    int? bleMaxInletAirTemperatureC,
    double? bleMinTirePressureFrKpa,
    double? bleMaxTirePressureFrKpa,
    double? bleMinTirePressureRrKpa,
    double? bleMaxTirePressureRrKpa,
    double? bleTripAKm,
    double? bleTripBKm,
    double? bleOdometerKm,
    double? behaviorMaxAccelG,
    double? behaviorMaxBrakeG,
    double? behaviorMaxCorneringG,
    int? behaviorHardAccelCount,
    int? behaviorHardBrakeCount,
    int? behaviorHardCorneringCount,
    double? best0To60Seconds,
    double? best100To180Seconds,
    double? phoneLeanMaxDeg,
  }) {
    return Trip(
      id: id,
      userId: userId,
      vehicleId: vehicleId,
      startedAt: startedAt,
      endedAt: endedAt,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      avgSpeedKph: avgSpeedKph,
      maxSpeedKph: maxSpeedKph,
      pointCount: pointCount,
      bleMaxSpeedKph: bleMaxSpeedKph,
      bleMaxRpm: bleMaxRpm,
      bleMaxLeanDeg: bleMaxLeanDeg,
      bleMaxBrakePressureKpa: bleMaxBrakePressureKpa,
      bleMinWaterTemperatureC: bleMinWaterTemperatureC,
      bleMaxWaterTemperatureC: bleMaxWaterTemperatureC,
      bleMaxThrottlePercent: bleMaxThrottlePercent,
      bleMaxAccelG: bleMaxAccelG,
      bleMaxTcsLevel: bleMaxTcsLevel,
      bleMinBattery12V: bleMinBattery12V,
      bleMaxBattery12V: bleMaxBattery12V,
      bleMinFuelGauge: bleMinFuelGauge,
      bleMaxFuelGauge: bleMaxFuelGauge,
      bleMinInletAirTemperatureC: bleMinInletAirTemperatureC,
      bleMaxInletAirTemperatureC: bleMaxInletAirTemperatureC,
      bleMinTirePressureFrKpa: bleMinTirePressureFrKpa,
      bleMaxTirePressureFrKpa: bleMaxTirePressureFrKpa,
      bleMinTirePressureRrKpa: bleMinTirePressureRrKpa,
      bleMaxTirePressureRrKpa: bleMaxTirePressureRrKpa,
      bleTripAKm: bleTripAKm,
      bleTripBKm: bleTripBKm,
      bleOdometerKm: bleOdometerKm,
      behaviorMaxAccelG: behaviorMaxAccelG,
      behaviorMaxBrakeG: behaviorMaxBrakeG,
      behaviorMaxCorneringG: behaviorMaxCorneringG,
      behaviorHardAccelCount: behaviorHardAccelCount,
      behaviorHardBrakeCount: behaviorHardBrakeCount,
      behaviorHardCorneringCount: behaviorHardCorneringCount,
      best0To60Seconds: best0To60Seconds,
      best100To180Seconds: best100To180Seconds,
      phoneLeanMaxDeg: phoneLeanMaxDeg,
    );
  }

  Map<String, Object?> toRow() => {
    'id': id,
    'user_id': userId,
    'vehicle_id': vehicleId,
    'started_at': startedAt.toIso8601String(),
    'ended_at': endedAt?.toIso8601String(),
    'distance_meters': distanceMeters,
    'duration_seconds': durationSeconds,
    'avg_speed_kph': avgSpeedKph,
    'max_speed_kph': maxSpeedKph,
    'point_count': pointCount,
    'ble_max_speed_kph': bleMaxSpeedKph,
    'ble_max_rpm': bleMaxRpm,
    'ble_max_lean_deg': bleMaxLeanDeg,
    'ble_max_brake_kpa': bleMaxBrakePressureKpa,
    'ble_min_water_temp_c': bleMinWaterTemperatureC,
    'ble_max_water_temp_c': bleMaxWaterTemperatureC,
    'ble_max_throttle_percent': bleMaxThrottlePercent,
    'ble_max_accel_g': bleMaxAccelG,
    'ble_max_tcs_level': bleMaxTcsLevel,
    'ble_min_battery_12v': bleMinBattery12V,
    'ble_max_battery_12v': bleMaxBattery12V,
    'ble_min_fuel_gauge': bleMinFuelGauge,
    'ble_max_fuel_gauge': bleMaxFuelGauge,
    'ble_min_inlet_air_temp_c': bleMinInletAirTemperatureC,
    'ble_max_inlet_air_temp_c': bleMaxInletAirTemperatureC,
    'ble_min_tire_pressure_fr_kpa': bleMinTirePressureFrKpa,
    'ble_max_tire_pressure_fr_kpa': bleMaxTirePressureFrKpa,
    'ble_min_tire_pressure_rr_kpa': bleMinTirePressureRrKpa,
    'ble_max_tire_pressure_rr_kpa': bleMaxTirePressureRrKpa,
    'ble_trip_a_km': bleTripAKm,
    'ble_trip_b_km': bleTripBKm,
    'ble_odometer_km': bleOdometerKm,
    'behavior_max_accel_g': behaviorMaxAccelG,
    'behavior_max_brake_g': behaviorMaxBrakeG,
    'behavior_max_cornering_g': behaviorMaxCorneringG,
    'behavior_hard_accel_count': behaviorHardAccelCount,
    'behavior_hard_brake_count': behaviorHardBrakeCount,
    'behavior_hard_cornering_count': behaviorHardCorneringCount,
    'best_0_60_seconds': best0To60Seconds,
    'best_100_180_seconds': best100To180Seconds,
    'phone_lean_max_deg': phoneLeanMaxDeg,
    'synced': synced ? 1 : 0,
  };

  static Trip fromRow(Map<String, Object?> row) => Trip(
    id: row['id'] as String,
    userId: row['user_id'] as String,
    vehicleId: row['vehicle_id'] as String,
    startedAt: DateTime.parse(row['started_at'] as String),
    endedAt: row['ended_at'] == null ? null : DateTime.parse(row['ended_at'] as String),
    distanceMeters: row['distance_meters'] as double,
    durationSeconds: row['duration_seconds'] as int,
    avgSpeedKph: row['avg_speed_kph'] as double?,
    maxSpeedKph: row['max_speed_kph'] as double?,
    pointCount: row['point_count'] as int,
    bleMaxSpeedKph: row['ble_max_speed_kph'] as double?,
    bleMaxRpm: row['ble_max_rpm'] as int?,
    bleMaxLeanDeg: row['ble_max_lean_deg'] as double?,
    bleMaxBrakePressureKpa: row['ble_max_brake_kpa'] as double?,
    bleMinWaterTemperatureC: row['ble_min_water_temp_c'] as int?,
    bleMaxWaterTemperatureC: row['ble_max_water_temp_c'] as int?,
    bleMaxThrottlePercent: row['ble_max_throttle_percent'] as double?,
    bleMaxAccelG: row['ble_max_accel_g'] as double?,
    bleMaxTcsLevel: row['ble_max_tcs_level'] as int?,
    bleMinBattery12V: row['ble_min_battery_12v'] as double?,
    bleMaxBattery12V: row['ble_max_battery_12v'] as double?,
    bleMinFuelGauge: row['ble_min_fuel_gauge'] as int?,
    bleMaxFuelGauge: row['ble_max_fuel_gauge'] as int?,
    bleMinInletAirTemperatureC: row['ble_min_inlet_air_temp_c'] as int?,
    bleMaxInletAirTemperatureC: row['ble_max_inlet_air_temp_c'] as int?,
    bleMinTirePressureFrKpa: row['ble_min_tire_pressure_fr_kpa'] as double?,
    bleMaxTirePressureFrKpa: row['ble_max_tire_pressure_fr_kpa'] as double?,
    bleMinTirePressureRrKpa: row['ble_min_tire_pressure_rr_kpa'] as double?,
    bleMaxTirePressureRrKpa: row['ble_max_tire_pressure_rr_kpa'] as double?,
    bleTripAKm: row['ble_trip_a_km'] as double?,
    bleTripBKm: row['ble_trip_b_km'] as double?,
    bleOdometerKm: row['ble_odometer_km'] as double?,
    behaviorMaxAccelG: row['behavior_max_accel_g'] as double?,
    behaviorMaxBrakeG: row['behavior_max_brake_g'] as double?,
    behaviorMaxCorneringG: row['behavior_max_cornering_g'] as double?,
    behaviorHardAccelCount: row['behavior_hard_accel_count'] as int?,
    behaviorHardBrakeCount: row['behavior_hard_brake_count'] as int?,
    behaviorHardCorneringCount: row['behavior_hard_cornering_count'] as int?,
    best0To60Seconds: row['best_0_60_seconds'] as double?,
    best100To180Seconds: row['best_100_180_seconds'] as double?,
    phoneLeanMaxDeg: row['phone_lean_max_deg'] as double?,
    synced: (row['synced'] as int? ?? 0) != 0,
  );

  /// What gets pushed to Supabase (supabase/schema.sql's `trips` table).
  Map<String, Object?> toSupabaseRow() => {
    'id': id,
    'user_id': userId,
    'vehicle_id': vehicleId,
    'started_at': startedAt.toIso8601String(),
    'ended_at': endedAt?.toIso8601String(),
    'distance_meters': distanceMeters,
    'duration_seconds': durationSeconds,
    'avg_speed_kph': avgSpeedKph,
    'max_speed_kph': maxSpeedKph,
    'point_count': pointCount,
    'ble_max_speed_kph': bleMaxSpeedKph,
    'ble_max_rpm': bleMaxRpm,
    'ble_max_lean_deg': bleMaxLeanDeg,
    'ble_max_brake_kpa': bleMaxBrakePressureKpa,
    'ble_min_water_temp_c': bleMinWaterTemperatureC,
    'ble_max_water_temp_c': bleMaxWaterTemperatureC,
    'ble_max_throttle_percent': bleMaxThrottlePercent,
    'ble_max_accel_g': bleMaxAccelG,
    'ble_max_tcs_level': bleMaxTcsLevel,
    'ble_min_battery_12v': bleMinBattery12V,
    'ble_max_battery_12v': bleMaxBattery12V,
    'ble_min_fuel_gauge': bleMinFuelGauge,
    'ble_max_fuel_gauge': bleMaxFuelGauge,
    'ble_min_inlet_air_temp_c': bleMinInletAirTemperatureC,
    'ble_max_inlet_air_temp_c': bleMaxInletAirTemperatureC,
    'ble_min_tire_pressure_fr_kpa': bleMinTirePressureFrKpa,
    'ble_max_tire_pressure_fr_kpa': bleMaxTirePressureFrKpa,
    'ble_min_tire_pressure_rr_kpa': bleMinTirePressureRrKpa,
    'ble_max_tire_pressure_rr_kpa': bleMaxTirePressureRrKpa,
    'ble_trip_a_km': bleTripAKm,
    'ble_trip_b_km': bleTripBKm,
    'ble_odometer_km': bleOdometerKm,
    'behavior_max_accel_g': behaviorMaxAccelG,
    'behavior_max_brake_g': behaviorMaxBrakeG,
    'behavior_max_cornering_g': behaviorMaxCorneringG,
    'behavior_hard_accel_count': behaviorHardAccelCount,
    'behavior_hard_brake_count': behaviorHardBrakeCount,
    'behavior_hard_cornering_count': behaviorHardCorneringCount,
    'best_0_60_seconds': best0To60Seconds,
    'best_100_180_seconds': best100To180Seconds,
    'phone_lean_max_deg': phoneLeanMaxDeg,
  };

  /// A row pulled from Supabase — always synced.
  static Trip fromSupabaseRow(Map<String, Object?> row) => Trip(
    id: row['id'] as String,
    userId: row['user_id'] as String,
    vehicleId: row['vehicle_id'] as String,
    startedAt: DateTime.parse(row['started_at'] as String),
    endedAt: row['ended_at'] == null ? null : DateTime.parse(row['ended_at'] as String),
    distanceMeters: (row['distance_meters'] as num).toDouble(),
    durationSeconds: row['duration_seconds'] as int,
    avgSpeedKph: (row['avg_speed_kph'] as num?)?.toDouble(),
    maxSpeedKph: (row['max_speed_kph'] as num?)?.toDouble(),
    pointCount: row['point_count'] as int,
    bleMaxSpeedKph: (row['ble_max_speed_kph'] as num?)?.toDouble(),
    bleMaxRpm: row['ble_max_rpm'] as int?,
    bleMaxLeanDeg: (row['ble_max_lean_deg'] as num?)?.toDouble(),
    bleMaxBrakePressureKpa: (row['ble_max_brake_kpa'] as num?)?.toDouble(),
    bleMinWaterTemperatureC: row['ble_min_water_temp_c'] as int?,
    bleMaxWaterTemperatureC: row['ble_max_water_temp_c'] as int?,
    bleMaxThrottlePercent: (row['ble_max_throttle_percent'] as num?)?.toDouble(),
    bleMaxAccelG: (row['ble_max_accel_g'] as num?)?.toDouble(),
    bleMaxTcsLevel: row['ble_max_tcs_level'] as int?,
    bleMinBattery12V: (row['ble_min_battery_12v'] as num?)?.toDouble(),
    bleMaxBattery12V: (row['ble_max_battery_12v'] as num?)?.toDouble(),
    bleMinFuelGauge: row['ble_min_fuel_gauge'] as int?,
    bleMaxFuelGauge: row['ble_max_fuel_gauge'] as int?,
    bleMinInletAirTemperatureC: row['ble_min_inlet_air_temp_c'] as int?,
    bleMaxInletAirTemperatureC: row['ble_max_inlet_air_temp_c'] as int?,
    bleMinTirePressureFrKpa: (row['ble_min_tire_pressure_fr_kpa'] as num?)?.toDouble(),
    bleMaxTirePressureFrKpa: (row['ble_max_tire_pressure_fr_kpa'] as num?)?.toDouble(),
    bleMinTirePressureRrKpa: (row['ble_min_tire_pressure_rr_kpa'] as num?)?.toDouble(),
    bleMaxTirePressureRrKpa: (row['ble_max_tire_pressure_rr_kpa'] as num?)?.toDouble(),
    bleTripAKm: (row['ble_trip_a_km'] as num?)?.toDouble(),
    bleTripBKm: (row['ble_trip_b_km'] as num?)?.toDouble(),
    bleOdometerKm: (row['ble_odometer_km'] as num?)?.toDouble(),
    behaviorMaxAccelG: (row['behavior_max_accel_g'] as num?)?.toDouble(),
    behaviorMaxBrakeG: (row['behavior_max_brake_g'] as num?)?.toDouble(),
    behaviorMaxCorneringG: (row['behavior_max_cornering_g'] as num?)?.toDouble(),
    behaviorHardAccelCount: row['behavior_hard_accel_count'] as int?,
    behaviorHardBrakeCount: row['behavior_hard_brake_count'] as int?,
    behaviorHardCorneringCount: row['behavior_hard_cornering_count'] as int?,
    best0To60Seconds: (row['best_0_60_seconds'] as num?)?.toDouble(),
    best100To180Seconds: (row['best_100_180_seconds'] as num?)?.toDouble(),
    phoneLeanMaxDeg: (row['phone_lean_max_deg'] as num?)?.toDouble(),
    synced: true,
  );
}
