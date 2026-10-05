/// A crew you belong to, with *your own* sharing settings for it — see
/// supabase/crews.sql's get_my_crews().
class Crew {
  final String id;
  final String name;
  final String ownerId;
  final int memberCount;
  final bool shareLocation;
  final bool shareSpeed;
  final bool shareLean;

  const Crew({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.memberCount,
    required this.shareLocation,
    required this.shareSpeed,
    required this.shareLean,
  });

  factory Crew.fromRow(Map<String, dynamic> row) => Crew(
        id: row['crew_id'] as String,
        name: row['name'] as String,
        ownerId: row['owner_id'] as String,
        memberCount: (row['member_count'] as num).toInt(),
        shareLocation: row['share_location'] as bool,
        shareSpeed: row['share_speed'] as bool,
        shareLean: row['share_lean'] as bool,
      );

  Crew copyWith({String? name, bool? shareLocation, bool? shareSpeed, bool? shareLean}) => Crew(
        id: id,
        name: name ?? this.name,
        ownerId: ownerId,
        memberCount: memberCount,
        shareLocation: shareLocation ?? this.shareLocation,
        shareSpeed: shareSpeed ?? this.shareSpeed,
        shareLean: shareLean ?? this.shareLean,
      );
}

/// See supabase/crews.sql's get_crew_members().
class CrewMember {
  final String userId;
  final String displayName;
  final bool isOwner;
  final bool shareLocation;

  const CrewMember({
    required this.userId,
    required this.displayName,
    required this.isOwner,
    required this.shareLocation,
  });

  factory CrewMember.fromRow(Map<String, dynamic> row) => CrewMember(
        userId: row['user_id'] as String,
        displayName: row['display_name'] as String,
        isOwner: row['is_owner'] as bool,
        shareLocation: row['share_location'] as bool,
      );
}

/// A crewmate currently riding and sharing their position with you — see
/// supabase/crews.sql's get_crew_live_positions(). [speedKph]/[leanDeg]
/// are null when they've turned sharing those off for every crew you
/// have in common (or simply don't have a reading).
class CrewLivePosition {
  final String userId;
  final String displayName;
  final String crewNames;
  final double latitude;
  final double longitude;
  final double? speedKph;
  final double? leanDeg;
  final double? headingDeg;
  final DateTime updatedAt;

  const CrewLivePosition({
    required this.userId,
    required this.displayName,
    required this.crewNames,
    required this.latitude,
    required this.longitude,
    required this.speedKph,
    required this.leanDeg,
    required this.headingDeg,
    required this.updatedAt,
  });

  factory CrewLivePosition.fromRow(Map<String, dynamic> row) => CrewLivePosition(
        userId: row['user_id'] as String,
        displayName: row['display_name'] as String,
        crewNames: (row['crew_names'] as String?) ?? '',
        latitude: (row['latitude'] as num).toDouble(),
        longitude: (row['longitude'] as num).toDouble(),
        speedKph: (row['speed_kph'] as num?)?.toDouble(),
        leanDeg: (row['lean_deg'] as num?)?.toDouble(),
        headingDeg: (row['heading_deg'] as num?)?.toDouble(),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );
}
