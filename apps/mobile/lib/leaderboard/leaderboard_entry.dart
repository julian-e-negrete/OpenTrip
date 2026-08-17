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

  const LeaderboardEntry({
    required this.userId,
    required this.displayName,
    required this.totalDistanceMeters,
    required this.longestDriveMeters,
    required this.territoryCells,
    required this.trophyCount,
  });

  factory LeaderboardEntry.fromRow(Map<String, dynamic> row) => LeaderboardEntry(
    userId: row['user_id'] as String,
    displayName: row['display_name'] as String,
    totalDistanceMeters: (row['total_distance_meters'] as num).toDouble(),
    longestDriveMeters: (row['longest_drive_meters'] as num).toDouble(),
    territoryCells: row['territory_cells'] as int,
    trophyCount: row['trophy_count'] as int,
  );
}

enum LeaderboardCategory { distance, longestDrive, territory, trophies }
