/// Local, per-user profile: a display name (shown instead of the email —
/// see auth/current_user.dart) and an optional avatar photo. Not yet
/// visible to any other user — there's no social/cross-user feature to
/// show it in yet (see docs/ROADMAP.md) — but this is the identity other
/// users will eventually see once cloud sync/leaderboards exist.
///
/// Only [displayName] syncs to Supabase (see sync/sync_service.dart) —
/// [avatarPath] is a local file path and stays local-only until photo
/// sync (Supabase Storage) is set up.
class UserProfile {
  final String userId;
  final String displayName;
  final String? avatarPath;
  final bool synced;

  const UserProfile({
    required this.userId,
    required this.displayName,
    this.avatarPath,
    this.synced = false,
  });

  UserProfile copyWith({String? displayName, String? avatarPath, bool? synced}) {
    return UserProfile(
      userId: userId,
      displayName: displayName ?? this.displayName,
      avatarPath: avatarPath ?? this.avatarPath,
      synced: synced ?? this.synced,
    );
  }

  Map<String, Object?> toRow() => {
    'user_id': userId,
    'display_name': displayName,
    'avatar_path': avatarPath,
    'synced': synced ? 1 : 0,
  };

  static UserProfile fromRow(Map<String, Object?> row) => UserProfile(
    userId: row['user_id'] as String,
    displayName: row['display_name'] as String,
    avatarPath: row['avatar_path'] as String?,
    synced: (row['synced'] as int? ?? 0) != 0,
  );

  Map<String, Object?> toSupabaseRow() => {'user_id': userId, 'display_name': displayName};

  static UserProfile fromSupabaseRow(Map<String, Object?> row, {String? localAvatarPath}) => UserProfile(
    userId: row['user_id'] as String,
    displayName: row['display_name'] as String,
    avatarPath: localAvatarPath,
    synced: true,
  );
}
