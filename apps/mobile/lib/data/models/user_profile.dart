/// Local, per-user profile: a display name (shown instead of the email —
/// see auth/current_user.dart), an optional avatar photo, an optional
/// country, and whether this rider wants to be ranked at all. Not yet
/// visible to any other user beyond what the leaderboard/territory map
/// deliberately expose (see docs/ROADMAP.md) — but this is the identity
/// other users see once they do.
///
/// [countryCode] is a picked ISO 3166-1 alpha-2 code (see
/// data/catalog/country_catalog.dart), not free text — the point of
/// capturing it now is that it stays usable later (e.g. a country-scoped
/// leaderboard slice), which a free-text field never reliably is.
///
/// [leaderboardVisible] is the "private profile" opt-out: false excludes
/// this rider from every cross-user ranking view (global leaderboard,
/// territory map, friends leaderboard — see get_leaderboard(),
/// get_territory_map(), get_friends_leaderboard() in
/// supabase/leaderboard.sql and supabase/friends.sql) without touching
/// sync itself — trips/vehicles/territory still sync, they just stop
/// being shown to anyone else.
///
/// [displayName], [countryCode], and [leaderboardVisible] sync to
/// Supabase (see sync/sync_service.dart) — [avatarPath] is a local file
/// path and stays local-only until photo sync (Supabase Storage) is set
/// up.
class UserProfile {
  final String userId;
  final String displayName;
  final String? avatarPath;
  final String? countryCode;
  final bool leaderboardVisible;
  final bool synced;

  const UserProfile({
    required this.userId,
    required this.displayName,
    this.avatarPath,
    this.countryCode,
    this.leaderboardVisible = true,
    this.synced = false,
  });

  UserProfile copyWith({
    String? displayName,
    String? avatarPath,
    String? countryCode,
    bool? leaderboardVisible,
    bool? synced,
  }) {
    return UserProfile(
      userId: userId,
      displayName: displayName ?? this.displayName,
      avatarPath: avatarPath ?? this.avatarPath,
      countryCode: countryCode ?? this.countryCode,
      leaderboardVisible: leaderboardVisible ?? this.leaderboardVisible,
      synced: synced ?? this.synced,
    );
  }

  Map<String, Object?> toRow() => {
    'user_id': userId,
    'display_name': displayName,
    'avatar_path': avatarPath,
    'country_code': countryCode,
    'leaderboard_visible': leaderboardVisible ? 1 : 0,
    'synced': synced ? 1 : 0,
  };

  static UserProfile fromRow(Map<String, Object?> row) => UserProfile(
    userId: row['user_id'] as String,
    displayName: row['display_name'] as String,
    avatarPath: row['avatar_path'] as String?,
    countryCode: row['country_code'] as String?,
    leaderboardVisible: (row['leaderboard_visible'] as int? ?? 1) != 0,
    synced: (row['synced'] as int? ?? 0) != 0,
  );

  Map<String, Object?> toSupabaseRow() => {
    'user_id': userId,
    'display_name': displayName,
    'country_code': countryCode,
    'leaderboard_visible': leaderboardVisible,
  };

  static UserProfile fromSupabaseRow(Map<String, Object?> row, {String? localAvatarPath}) => UserProfile(
    userId: row['user_id'] as String,
    displayName: row['display_name'] as String,
    avatarPath: localAvatarPath,
    countryCode: row['country_code'] as String?,
    leaderboardVisible: (row['leaderboard_visible'] as bool?) ?? true,
    synced: true,
  );
}
