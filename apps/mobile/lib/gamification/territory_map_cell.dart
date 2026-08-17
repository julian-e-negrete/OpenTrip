/// One row of supabase/leaderboard.sql's get_territory_map() function —
/// which cell, whose it is, and their display name. Deliberately just
/// that: no raw trip routes or timestamps, same "expose an aggregate, not
/// the private data behind it" reasoning as get_leaderboard() (see that
/// function's comment in leaderboard.sql). A cell only says someone rode
/// through roughly that ~1.1km square at some point, not when or by what
/// path.
class TerritoryMapCell {
  final String cellKey;
  final String userId;
  final String displayName;

  const TerritoryMapCell({required this.cellKey, required this.userId, required this.displayName});

  factory TerritoryMapCell.fromRow(Map<String, dynamic> row) => TerritoryMapCell(
    cellKey: row['cell_key'] as String,
    userId: row['user_id'] as String,
    displayName: row['display_name'] as String,
  );
}
