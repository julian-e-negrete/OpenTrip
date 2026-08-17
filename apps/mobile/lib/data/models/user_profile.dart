/// Local, per-user profile: a display name (shown instead of the email —
/// see auth/current_user.dart) and an optional avatar photo. Not yet
/// visible to any other user — there's no social/cross-user feature to
/// show it in yet (see docs/ROADMAP.md) — but this is the identity other
/// users will eventually see once cloud sync/leaderboards exist.
class UserProfile {
  final String userId;
  final String displayName;
  final String? avatarPath;

  const UserProfile({required this.userId, required this.displayName, this.avatarPath});

  UserProfile copyWith({String? displayName, String? avatarPath}) {
    return UserProfile(
      userId: userId,
      displayName: displayName ?? this.displayName,
      avatarPath: avatarPath ?? this.avatarPath,
    );
  }

  Map<String, Object?> toRow() => {
    'user_id': userId,
    'display_name': displayName,
    'avatar_path': avatarPath,
  };

  static UserProfile fromRow(Map<String, Object?> row) => UserProfile(
    userId: row['user_id'] as String,
    displayName: row['display_name'] as String,
    avatarPath: row['avatar_path'] as String?,
  );
}
