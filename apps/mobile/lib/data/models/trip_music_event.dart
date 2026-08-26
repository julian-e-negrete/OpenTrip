/// One track change during a trip, captured from Spotify's own local
/// "now playing" broadcast (see trip/spotify_now_playing.dart) — a
/// sparse, event-driven timeline (one row per track change, not one per
/// GPS fix like trip_points), so it gets its own table rather than
/// riding along on trip_points the way BLE telemetry does.
class TripMusicEvent {
  final String tripId;
  final int seq;
  final String track;
  final String? artist;
  final String? album;
  final String? spotifyUri;
  final DateTime startedAt;

  const TripMusicEvent({
    required this.tripId,
    required this.seq,
    required this.track,
    this.artist,
    this.album,
    this.spotifyUri,
    required this.startedAt,
  });

  Map<String, Object?> toRow() => {
    'trip_id': tripId,
    'seq': seq,
    'track': track,
    'artist': artist,
    'album': album,
    'spotify_uri': spotifyUri,
    'started_at': startedAt.toIso8601String(),
  };

  static TripMusicEvent fromRow(Map<String, Object?> row) => TripMusicEvent(
    tripId: row['trip_id'] as String,
    seq: row['seq'] as int,
    track: row['track'] as String,
    artist: row['artist'] as String?,
    album: row['album'] as String?,
    spotifyUri: row['spotify_uri'] as String?,
    startedAt: DateTime.parse(row['started_at'] as String),
  );

  /// What gets pushed to Supabase (supabase/schema.sql's
  /// `trip_music_events` table) — identical shape to [toRow], kept
  /// separate for the same reason trip_point.dart's toSupabaseRow is:
  /// the local/remote schemas can drift independently, and `"timestamp"`-
  /// style quoted-reserved-word concerns are explicit here, not implied.
  Map<String, Object?> toSupabaseRow() => {
    'trip_id': tripId,
    'seq': seq,
    'track': track,
    'artist': artist,
    'album': album,
    'spotify_uri': spotifyUri,
    'started_at': startedAt.toIso8601String(),
  };

  static TripMusicEvent fromSupabaseRow(Map<String, Object?> row) => TripMusicEvent(
    tripId: row['trip_id'] as String,
    seq: row['seq'] as int,
    track: row['track'] as String,
    artist: row['artist'] as String?,
    album: row['album'] as String?,
    spotifyUri: row['spotify_uri'] as String?,
    startedAt: DateTime.parse(row['started_at'] as String),
  );
}
