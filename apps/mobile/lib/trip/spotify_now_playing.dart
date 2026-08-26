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
