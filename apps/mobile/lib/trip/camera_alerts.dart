import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

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

  static const _alertRadiusMeters = 500.0;
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
      request.write('data=${Uri.encodeQueryComponent(query)}');
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return;

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
    } catch (_) {
      // Best-effort — no network, Overpass unavailable/rate-limiting, or a
      // malformed response just means no alerts for this stretch of the
      // trip, not a failed recording.
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
        // A physical cue works whether or not anyone's looking at a
        // screen right now — the point of a driving alert.
        unawaited(HapticFeedback.vibrate());
        _alertController.add(CameraAlert(camera, distance));
      }
    }
  }

  Future<void> dispose() async {
    await _alertController.close();
  }
}
