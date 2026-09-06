/// One row of supabase/leaderboard.sql's get_leaderboard() function —
/// already-aggregated numbers, never raw trip/route data (see that file's
/// comment for why a function instead of a view was necessary here).
class LeaderboardEntry {
  final String userId;
  final String displayName;
  final double totalDistanceMeters;
  final double longestDriveMeters;
  final int territoryCells;
  final int trophyCount;

  /// Racing stats (trip/accel_run_tracker.dart) — best (lowest) 0-60/
  /// 100-180 km/h time across this rider's trips, and their highest-ever
  /// recorded top speed. Null until a trip actually crosses that bracket.
  final double? best0To60Seconds;
  final double? best100To180Seconds;
  final double? topSpeedKph;

  const LeaderboardEntry({
    required this.userId,
    required this.displayName,
    required this.totalDistanceMeters,
    required this.longestDriveMeters,
    required this.territoryCells,
    required this.trophyCount,
    this.best0To60Seconds,
    this.best100To180Seconds,
    this.topSpeedKph,
  });

  factory LeaderboardEntry.fromRow(Map<String, dynamic> row) => LeaderboardEntry(
    userId: row['user_id'] as String,
    displayName: row['display_name'] as String,
    totalDistanceMeters: (row['total_distance_meters'] as num).toDouble(),
    longestDriveMeters: (row['longest_drive_meters'] as num).toDouble(),
    territoryCells: row['territory_cells'] as int,
    trophyCount: row['trophy_count'] as int,
    best0To60Seconds: (row['best_0_60_seconds'] as num?)?.toDouble(),
    best100To180Seconds: (row['best_100_180_seconds'] as num?)?.toDouble(),
    topSpeedKph: (row['top_speed_kph'] as num?)?.toDouble(),
  );
}

enum LeaderboardCategory { distance, longestDrive, territory, trophies }
