import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';

import '../logging/error_reporter.dart';
import '../logging/log_buffer.dart';
import 'geo_math.dart';

enum CameraAlertType { speedCamera, redLightCamera }

class CameraPoint {
  /// The OSM node id — used to dedupe so the same camera doesn't alert
  /// twice in one trip even after a re-query refreshes the cached list.
  final String id;
  final double latitude;
  final double longitude;
  final CameraAlertType type;

  const CameraPoint({required this.id, required this.latitude, required this.longitude, required this.type});
}

class CameraAlert {
  final CameraPoint camera;
  final double distanceMeters;
  const CameraAlert(this.camera, this.distanceMeters);
}

/// Speed-camera and red-light-camera proximity alerts, fed by GPS
/// positions from trip/location_recorder.dart during a recording.
///
/// Deliberately doesn't alert on plain traffic signals — OpenStreetMap's
/// `highway=traffic_signals` tag exists at nearly every intersection in
/// a city, and alerting on every one would just be noise, not safety
/// information (not what real navigation apps do either). Only actual
/// enforcement points are worth interrupting a drive for: fixed speed
/// cameras (`highway=speed_camera`, the older tagging convention, or
/// `enforcement=maxspeed`, the current one) and red-light cameras
/// (`enforcement=traffic_signals`) — see OSM's Enforcement proposal for
/// why these are separate tags from the signal/limit itself.
///
/// Data comes from the public Overpass API (overpass-api.de) — the same
/// OpenStreetMap data trips/trip_detail_screen.dart's map tiles already
/// depend on, with the same fair-use caveat that comment documents: fine
/// at this app's current scale, not meant for high-volume automated
/// querying. Kept well inside that by querying once per trip and again
/// only every [_requeryDistanceMeters] of travel — never per GPS fix.
/// Coverage is only as good as OpenStreetMap's in a given area, which
/// varies a lot by country/region, same as the map tiles themselves.
class CameraAlertService {
  final _alertController = StreamController<CameraAlert>.broadcast();
  Stream<CameraAlert> get alerts => _alertController.stream;
  final _audioPlayer = AudioPlayer();
  bool _audioContextConfigured = false;

  /// The cameras loaded for the current stretch — so the map can plot
  /// them ahead of time, not just react once you're within alert range.
  final camerasNotifier = ValueNotifier<List<CameraPoint>>(const []);

  // Alerts within this radius, but at highway speed a GPS fix can land
  // anywhere inside it (fixes arrive every few seconds, not continuously)
  // — the actual trigger distance ranges from here down to 0m depending
  // on where the next fix happens to fall, not a fixed lead time. 1km
  // keeps that whole range comfortably ahead of the camera instead of
  // sometimes as close as a couple hundred meters.
  static const _alertRadiusMeters = 1000.0;
  static const _requeryDistanceMeters = 15000.0;
  static const _queryRadiusDegrees = 0.09; // ~10km at most latitudes

  List<CameraPoint> _cameras = [];
  final _alertedIds = <String>{};
  Position? _lastQueriedAt;
  bool _queryInFlight = false;

  /// Clears which cameras have already alerted — call at the start of a
  /// new trip so passing the same camera again on a later trip still
  /// alerts. Deliberately keeps the cached camera list and last-query
  /// position, since those are just a network cache tied to geography,
  /// not to any one trip.
  void resetForNewTrip() => _alertedIds.clear();

  /// Loads (or reuses the cached) camera list for [position] without
  /// proximity-checking or alerting — for showing cameras on the map
  /// before a recording starts, when there's nothing to alert about yet.
  /// Recording itself still drives [onPosition] as the rider moves.
  Future<void> loadNear(Position position) async {
    if (_shouldRequery(position)) await _query(position);
  }

  Future<void> onPosition(Position position) async {
    if (_shouldRequery(position)) {
      unawaited(_query(position));
    }
    _checkProximity(position);
  }

  bool _shouldRequery(Position position) {
    if (_queryInFlight) return false;
    final last = _lastQueriedAt;
    if (last == null) return true;
    final movedMeters = haversineMeters(
      lat1: last.latitude,
      lon1: last.longitude,
      lat2: position.latitude,
      lon2: position.longitude,
    );
    return movedMeters >= _requeryDistanceMeters;
  }

  Future<void> _query(Position position) async {
    _queryInFlight = true;
    _lastQueriedAt = position;
    logBuffer.add(
      'Camera: querying Overpass around '
      '(${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})',
    );
    HttpClient? client;
    try {
      final south = position.latitude - _queryRadiusDegrees;
      final north = position.latitude + _queryRadiusDegrees;
      final west = position.longitude - _queryRadiusDegrees;
      final east = position.longitude + _queryRadiusDegrees;
      final bbox = '$south,$west,$north,$east';
      final query =
          '[out:json][timeout:20];'
          '('
          'node["highway"="speed_camera"]($bbox);'
          'node["enforcement"="maxspeed"]($bbox);'
          'node["enforcement"="traffic_signals"]($bbox);'
          ');'
          'out body;';

      client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
      final request = await client.postUrl(Uri.parse('https://overpass-api.de/api/interpreter'));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
      // Overpass rejects requests carrying Dart's default HttpClient User-Agent
      // (a generic "Dart/<version> (dart:io)" string) with a flat HTTP 406 —
      // confirmed live, this silently broke every camera query. A real
      // identifier, same convention as the map tiles' userAgentPackageName,
      // is what their fair-use policy actually asks for anyway.
      request.headers.set(HttpHeaders.userAgentHeader, 'co.opentrip.opentrip_mobile');
      request.write('data=${Uri.encodeQueryComponent(query)}');
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        logBuffer.add('Camera: Overpass returned HTTP ${response.statusCode}, keeping previous cache');
        return;
      }

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final elements = (json['elements'] as List?) ?? const [];

      _cameras = elements
          .whereType<Map<String, dynamic>>()
          .map((e) {
            final tags = (e['tags'] as Map?) ?? const {};
            final lat = e['lat'] as num?;
            final lon = e['lon'] as num?;
            if (lat == null || lon == null) return null;
            final type = tags['enforcement'] == 'traffic_signals'
                ? CameraAlertType.redLightCamera
                : CameraAlertType.speedCamera;
            return CameraPoint(id: '${e['id']}', latitude: lat.toDouble(), longitude: lon.toDouble(), type: type);
          })
          .whereType<CameraPoint>()
          .toList();
      camerasNotifier.value = _cameras;
      logBuffer.add('Camera: loaded ${_cameras.length} camera(s) for this stretch');
    } catch (e, st) {
      // Best-effort — no network, Overpass unavailable/rate-limiting, or a
      // malformed response just means no alerts for this stretch of the
      // trip, not a failed recording.
      logBuffer.add('Camera: query failed, no alerts for this stretch — $e');
      unawaited(ErrorReporter.report('Camera: Overpass query', e, st));
    } finally {
      client?.close();
      _queryInFlight = false;
    }
  }

  void _checkProximity(Position position) {
    for (final camera in _cameras) {
      if (_alertedIds.contains(camera.id)) continue;
      final distance = haversineMeters(
        lat1: position.latitude,
        lon1: position.longitude,
        lat2: camera.latitude,
        lon2: camera.longitude,
      );
      if (distance <= _alertRadiusMeters) {
        _alertedIds.add(camera.id);
        logBuffer.add('Camera: ${camera.type.name} alert — ${distance.toStringAsFixed(0)}m away');
        // A physical cue works whether or not anyone's looking at a
        // screen right now — the point of a driving alert. This needs to
        // be a real, sustained buzz a rider can feel over a moving
        // motorcycle's own vibration and wind noise — flutter/services.dart's
        // HapticFeedback is a brief UI-click tick meant for a button tap,
        // not an alert; effectively imperceptible in that context, which
        // is exactly what "alerts do not vibrate" turned out to mean.
        unawaited(_buzz());
        unawaited(_beep());
        _alertController.add(CameraAlert(camera, distance));
      }
    }
  }

  Future<void> _buzz() async {
    try {
      if (!await Vibration.hasVibrator()) return;
      // Three deliberate pulses, not one short tick — meant to be felt
      // over engine vibration/wind noise, and distinct enough from any
      // other haptic in the app that it reads as "look at the road", not
      // just background phone noise.
      await Vibration.vibrate(pattern: [0, 300, 150, 300, 150, 300]);
    } catch (e, st) {
      logBuffer.add('Camera: vibration failed — $e');
      unawaited(ErrorReporter.report('Camera: vibration', e, st));
    }
  }

  Future<void> _beep() async {
    try {
      if (!_audioContextConfigured) {
        // audioplayers defaults to AndroidAudioFocus.gain/no iOS mixing —
        // "this app is now the sole source of audio," which pauses or
        // stops whatever else is playing, including the rider's own music
        // (spotify_now_playing.dart just logs what's playing, it doesn't
        // own the audio session, so this alert was the one silencing it).
        // duckOthers instead just lowers other audio while this plays on
        // top, the same way a GPS voice prompt or alarm layers over music
        // rather than cutting it off.
        await _audioPlayer.setAudioContext(AudioContextConfig(focus: AudioContextConfigFocus.duckOthers).build());
        _audioContextConfigured = true;
      }
      // Same three-pulse cadence as _buzz — an audible cue reaches a
      // rider whose phone isn't in a pocket (mounted, or a helmet
      // intercom paired over Bluetooth) the way vibration alone can't.
      await _audioPlayer.play(AssetSource('sounds/camera_alert.wav'));
    } catch (e, st) {
      logBuffer.add('Camera: alert sound failed — $e');
      unawaited(ErrorReporter.report('Camera: alert sound', e, st));
    }
  }

  Future<void> dispose() async {
    camerasNotifier.dispose();
    await _audioPlayer.dispose();
    await _alertController.close();
  }
}
