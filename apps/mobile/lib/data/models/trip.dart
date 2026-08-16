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
  });

  bool get isFinished => endedAt != null;

  double get distanceKm => distanceMeters / 1000.0;

  Trip finish({
    required DateTime endedAt,
    required double distanceMeters,
    required int durationSeconds,
    required double? avgSpeedKph,
    required double? maxSpeedKph,
    required int pointCount,
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
  );
}
