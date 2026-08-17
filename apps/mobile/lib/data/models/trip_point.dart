class TripPoint {
  final String tripId;
  final int seq;
  final double latitude;
  final double longitude;
  final double? altitudeMeters;
  final double? speedKph;
  final DateTime timestamp;

  const TripPoint({
    required this.tripId,
    required this.seq,
    required this.latitude,
    required this.longitude,
    this.altitudeMeters,
    this.speedKph,
    required this.timestamp,
  });

  Map<String, Object?> toRow() => {
    'trip_id': tripId,
    'seq': seq,
    'latitude': latitude,
    'longitude': longitude,
    'altitude_meters': altitudeMeters,
    'speed_kph': speedKph,
    'timestamp': timestamp.toIso8601String(),
  };

  static TripPoint fromRow(Map<String, Object?> row) => TripPoint(
    tripId: row['trip_id'] as String,
    seq: row['seq'] as int,
    latitude: row['latitude'] as double,
    longitude: row['longitude'] as double,
    altitudeMeters: row['altitude_meters'] as double?,
    speedKph: row['speed_kph'] as double?,
    timestamp: DateTime.parse(row['timestamp'] as String),
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
  };

  static TripPoint fromSupabaseRow(Map<String, Object?> row) => TripPoint(
    tripId: row['trip_id'] as String,
    seq: row['seq'] as int,
    latitude: (row['latitude'] as num).toDouble(),
    longitude: (row['longitude'] as num).toDouble(),
    altitudeMeters: (row['altitude_meters'] as num?)?.toDouble(),
    speedKph: (row['speed_kph'] as num?)?.toDouble(),
    timestamp: DateTime.parse(row['timestamp'] as String),
  );
}
