/// Local, per-user profile: a display name (shown instead of the email —
/// see auth/current_user.dart), an optional avatar photo, and an optional
/// country. Not yet visible to any other user — there's no social/
/// cross-user feature to show it in yet (see docs/ROADMAP.md) — but this
/// is the identity other users will eventually see once cloud sync/
/// leaderboards exist.
///
/// [countryCode] is a picked ISO 3166-1 alpha-2 code (see
/// data/catalog/country_catalog.dart), not free text — the point of
/// capturing it now is that it stays usable later (e.g. a country-scoped
/// leaderboard slice), which a free-text field never reliably is.
///
/// [displayName] and [countryCode] sync to Supabase (see
/// sync/sync_service.dart) — [avatarPath] is a local file path and stays
/// local-only until photo sync (Supabase Storage) is set up.
class UserProfile {
  final String userId;
  final String displayName;
  final String? avatarPath;
  final String? countryCode;
  final bool synced;

  const UserProfile({
    required this.userId,
    required this.displayName,
    this.avatarPath,
    this.countryCode,
    this.synced = false,
  });

  UserProfile copyWith({String? displayName, String? avatarPath, String? countryCode, bool? synced}) {
    return UserProfile(
      userId: userId,
      displayName: displayName ?? this.displayName,
      avatarPath: avatarPath ?? this.avatarPath,
      countryCode: countryCode ?? this.countryCode,
      synced: synced ?? this.synced,
    );
  }

  Map<String, Object?> toRow() => {
    'user_id': userId,
    'display_name': displayName,
    'avatar_path': avatarPath,
    'country_code': countryCode,
    'synced': synced ? 1 : 0,
  };

  static UserProfile fromRow(Map<String, Object?> row) => UserProfile(
    userId: row['user_id'] as String,
    displayName: row['display_name'] as String,
    avatarPath: row['avatar_path'] as String?,
    countryCode: row['country_code'] as String?,
    synced: (row['synced'] as int? ?? 0) != 0,
  );

  Map<String, Object?> toSupabaseRow() => {
    'user_id': userId,
    'display_name': displayName,
    'country_code': countryCode,
  };

  static UserProfile fromSupabaseRow(Map<String, Object?> row, {String? localAvatarPath}) => UserProfile(
    userId: row['user_id'] as String,
    displayName: row['display_name'] as String,
    avatarPath: localAvatarPath,
    countryCode: row['country_code'] as String?,
    synced: true,
  );
}
