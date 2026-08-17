/// A rider found via search, or one of your accepted friends — just
/// enough to show a name and act on. See supabase/friends.sql's
/// search_riders()/get_friends().
class RiderSummary {
  final String userId;
  final String displayName;

  const RiderSummary({required this.userId, required this.displayName});

  factory RiderSummary.fromRow(Map<String, dynamic> row) =>
      RiderSummary(userId: row['user_id'] as String, displayName: row['display_name'] as String);
}

/// An incoming friend request, still pending your response. See
/// supabase/friends.sql's get_pending_friend_requests().
class PendingFriendRequest {
  final String requesterId;
  final String displayName;
  final DateTime requestedAt;

  const PendingFriendRequest({required this.requesterId, required this.displayName, required this.requestedAt});

  factory PendingFriendRequest.fromRow(Map<String, dynamic> row) => PendingFriendRequest(
    requesterId: row['requester_id'] as String,
    displayName: row['display_name'] as String,
    requestedAt: DateTime.parse(row['requested_at'] as String),
  );
}
