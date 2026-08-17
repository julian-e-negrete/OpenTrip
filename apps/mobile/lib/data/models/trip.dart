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
    this.synced = false,
  });

  bool get hasBleTelemetry => bleMaxSpeedKph != null || bleMaxRpm != null;

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
    synced: true,
  );
}
