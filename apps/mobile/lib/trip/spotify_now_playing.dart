import 'package:flutter/services.dart';

/// One "track started" event, as sent by Spotify's Android app's own
/// `com.spotify.music.metadatachanged` local broadcast — see
/// android/app/src/main/kotlin/co/opentrip/opentrip_mobile/SpotifyNowPlayingStreamHandler.kt
/// for the native side. This is deliberately *not* Spotify's Web API:
/// no OAuth, no developer-app registration, no per-app user cap — just a
/// local Android intent Spotify already sends, gated only by the user
/// turning on "Device Broadcast Status" in Spotify's own Settings ->
/// Playback. See docs/ROADMAP.md for the fuller why.
class SpotifyTrackEvent {
  final String track;
  final String? artist;
  final String? album;
  final String? spotifyUri;

  /// When Spotify's own broadcast says it was sent (`timeSentMs`) — *not*
  /// necessarily when this app actually received it. Don't use this for
  /// "how far into the trip did this track start" (see
  /// trip/recording_screen.dart, which stamps trip/data/models/trip_music_event.dart's
  /// startedAt with the receive-time DateTime.now() instead): the very
  /// first broadcast a freshly-registered receiver gets can be a replay
  /// of whatever was already playing, carrying a `timeSentMs` from
  /// whenever that track actually started — which, if it's been playing
  /// a while, reads as a wildly large "N hours in" once compared against
  /// the trip's actual start time. Kept here only as informational
  /// metadata about the broadcast itself.
  final DateTime timestamp;

  const SpotifyTrackEvent({
    required this.track,
    this.artist,
    this.album,
    this.spotifyUri,
    required this.timestamp,
  });

  factory SpotifyTrackEvent.fromMap(Map<Object?, Object?> map) => SpotifyTrackEvent(
    track: map['track'] as String,
    artist: map['artist'] as String?,
    album: map['album'] as String?,
    spotifyUri: map['spotifyUri'] as String?,
    timestamp: DateTime.fromMillisecondsSinceEpoch(map['timeSentMs'] as int),
  );
}

/// Android-only — there's no native handler wired up for any other
/// platform (see MainActivity.kt), matching this app's Android-only
/// scope. [trackChanges] is a broadcast stream: every listener gets
/// every event from whenever they start listening, same as
/// vehicle/ble_connection_service.dart's telemetry stream.
class SpotifyNowPlaying {
  SpotifyNowPlaying._();
  static final instance = SpotifyNowPlaying._();

  static const _channel = EventChannel('co.opentrip.opentrip_mobile/spotify_now_playing');

  Stream<SpotifyTrackEvent>? _stream;

  Stream<SpotifyTrackEvent> get trackChanges {
    return _stream ??= _channel
        .receiveBroadcastStream()
        .map((event) => SpotifyTrackEvent.fromMap(event as Map<Object?, Object?>));
  }
}
