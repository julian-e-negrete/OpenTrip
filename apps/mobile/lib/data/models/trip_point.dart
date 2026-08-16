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
}
