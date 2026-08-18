/// One row of supabase/leaderboard.sql's get_territory_map() function —
/// which cell, whose it is, their display name, and how many times
/// they've ridden through it. Deliberately just that: no raw trip routes
/// or timestamps, same "expose an aggregate, not the private data behind
/// it" reasoning as get_leaderboard() (see that function's comment in
/// leaderboard.sql). A cell only says someone rode through roughly that
/// ~1.1km square, and how many times, not when or by what path.
class TerritoryMapCell {
  final String cellKey;
  final String userId;
  final String displayName;
  final int visitCount;

  const TerritoryMapCell({
    required this.cellKey,
    required this.userId,
    required this.displayName,
    required this.visitCount,
  });

  factory TerritoryMapCell.fromRow(Map<String, dynamic> row) => TerritoryMapCell(
    cellKey: row['cell_key'] as String,
    userId: row['user_id'] as String,
    displayName: row['display_name'] as String,
    // Defaults to 1 so a row from a not-yet-migrated backend (visit_count
    // added after this column shipped) still renders instead of crashing.
    visitCount: (row['visit_count'] as num?)?.toInt() ?? 1,
  );
}
