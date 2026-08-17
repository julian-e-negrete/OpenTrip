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

  /// Whether this trip (and its points) has been pushed to Supabase. See
  /// sync/sync_service.dart. Always true for a trip that came from a pull.
  final bool synced;

  /// Whether autostart/driving_detector_task.dart created this trip
  /// itself (detected via ActivityRecognition, no one tapped "Start
  /// recording") rather than a manual recording. Purely local bookkeeping
  /// — it's how the detector task tells "a trip I own and should
  /// auto-stop" apart from a manual one it must leave alone, and how
  /// trip/recording_screen.dart tells "adopt this already-running trip"
  /// apart from "let me start a new one." Not synced — another device
  /// doesn't need to know which button (or lack of one) started a trip.
  final bool autoStarted;

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
    this.behaviorMaxAccelG,
    this.behaviorMaxBrakeG,
    this.behaviorMaxCorneringG,
    this.behaviorHardAccelCount,
    this.behaviorHardBrakeCount,
    this.behaviorHardCorneringCount,
    this.synced = false,
    this.autoStarted = false,
  });

  bool get hasBleTelemetry => bleMaxSpeedKph != null || bleMaxRpm != null;

  bool get hasBehaviorStats => behaviorMaxAccelG != null || behaviorMaxBrakeG != null || behaviorMaxCorneringG != null;

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
    double? behaviorMaxAccelG,
    double? behaviorMaxBrakeG,
    double? behaviorMaxCorneringG,
    int? behaviorHardAccelCount,
    int? behaviorHardBrakeCount,
    int? behaviorHardCorneringCount,
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
      behaviorMaxAccelG: behaviorMaxAccelG,
      behaviorMaxBrakeG: behaviorMaxBrakeG,
      behaviorMaxCorneringG: behaviorMaxCorneringG,
      behaviorHardAccelCount: behaviorHardAccelCount,
      behaviorHardBrakeCount: behaviorHardBrakeCount,
      behaviorHardCorneringCount: behaviorHardCorneringCount,
      autoStarted: autoStarted,
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
    'behavior_max_accel_g': behaviorMaxAccelG,
    'behavior_max_brake_g': behaviorMaxBrakeG,
    'behavior_max_cornering_g': behaviorMaxCorneringG,
    'behavior_hard_accel_count': behaviorHardAccelCount,
    'behavior_hard_brake_count': behaviorHardBrakeCount,
    'behavior_hard_cornering_count': behaviorHardCorneringCount,
    'auto_started': autoStarted ? 1 : 0,
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
    behaviorMaxAccelG: row['behavior_max_accel_g'] as double?,
    behaviorMaxBrakeG: row['behavior_max_brake_g'] as double?,
    behaviorMaxCorneringG: row['behavior_max_cornering_g'] as double?,
    behaviorHardAccelCount: row['behavior_hard_accel_count'] as int?,
    behaviorHardBrakeCount: row['behavior_hard_brake_count'] as int?,
    behaviorHardCorneringCount: row['behavior_hard_cornering_count'] as int?,
    autoStarted: (row['auto_started'] as int? ?? 0) != 0,
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
    'behavior_max_accel_g': behaviorMaxAccelG,
    'behavior_max_brake_g': behaviorMaxBrakeG,
    'behavior_max_cornering_g': behaviorMaxCorneringG,
    'behavior_hard_accel_count': behaviorHardAccelCount,
    'behavior_hard_brake_count': behaviorHardBrakeCount,
    'behavior_hard_cornering_count': behaviorHardCorneringCount,
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
    behaviorMaxAccelG: (row['behavior_max_accel_g'] as num?)?.toDouble(),
    behaviorMaxBrakeG: (row['behavior_max_brake_g'] as num?)?.toDouble(),
    behaviorMaxCorneringG: (row['behavior_max_cornering_g'] as num?)?.toDouble(),
    behaviorHardAccelCount: row['behavior_hard_accel_count'] as int?,
    behaviorHardBrakeCount: row['behavior_hard_brake_count'] as int?,
    behaviorHardCorneringCount: row['behavior_hard_cornering_count'] as int?,
    synced: true,
  );
}
