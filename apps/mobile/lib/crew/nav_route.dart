import 'dart:convert';
import 'dart:io';

import '../trip/geo_math.dart';

/// One turn instruction of a route, from OSRM's `steps` output.
class NavStep {
  /// OSRM maneuver type: turn, new name, depart, arrive, merge, fork,
  /// on ramp, off ramp, end of road, continue, roundabout, rotary, ...
  final String type;

  /// left, slight left, sharp left, right, ..., straight, uturn — or null.
  final String? modifier;

  /// Street name of the road *after* this maneuver ('' if unnamed).
  final String name;

  /// Roundabout exit number, when [type] is a roundabout/rotary.
  final int? exit;

  /// Where the maneuver happens.
  final double latitude;
  final double longitude;

  /// Length of the leg that *follows* this maneuver, in meters.
  final double distanceMeters;

  const NavStep({
    required this.type,
    required this.modifier,
    required this.name,
    required this.exit,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
  });

  /// Human-readable instruction, e.g. "Turn left onto Av. Corrientes".
  String get instruction {
    final onto = name.isEmpty ? '' : ' onto $name';
    final dir = modifier ?? '';
    switch (type) {
      case 'depart':
        return name.isEmpty ? 'Head out' : 'Head out on $name';
      case 'arrive':
        return 'Arrive at your crewmate';
      case 'roundabout':
      case 'rotary':
      case 'roundabout turn':
        return exit == null ? 'Enter the roundabout$onto' : 'At the roundabout, take exit $exit$onto';
      case 'merge':
        return 'Merge${dir.isEmpty ? '' : ' $dir'}$onto';
      case 'on ramp':
        return 'Take the ramp${dir.isEmpty ? '' : ' on the $dir'}$onto';
      case 'off ramp':
        return 'Take the exit${dir.isEmpty ? '' : ' on the $dir'}$onto';
      case 'fork':
        return 'Keep ${dir.isEmpty ? 'ahead' : dir.replaceFirst('slight ', '')} at the fork$onto';
      case 'end of road':
        return 'At the end of the road, turn ${dir.isEmpty ? 'ahead' : dir}$onto';
      case 'continue':
      case 'new name':
        if (dir == 'uturn') return 'Make a U-turn$onto';
        return 'Continue${dir.isEmpty || dir == 'straight' ? '' : ' $dir'}$onto';
      default:
        if (dir == 'uturn') return 'Make a U-turn$onto';
        if (dir == 'straight') return 'Go straight$onto';
        return dir.isEmpty ? 'Continue$onto' : 'Turn $dir$onto';
    }
  }

  factory NavStep.fromOsrm(Map<String, dynamic> step) {
    final maneuver = step['maneuver'] as Map<String, dynamic>;
    final location = (maneuver['location'] as List).cast<num>();
    return NavStep(
      type: maneuver['type'] as String,
      modifier: maneuver['modifier'] as String?,
      name: (step['name'] as String?) ?? '',
      exit: (maneuver['exit'] as num?)?.toInt(),
      longitude: location[0].toDouble(),
      latitude: location[1].toDouble(),
      distanceMeters: (step['distance'] as num).toDouble(),
    );
  }
}

typedef NavLatLon = (double lat, double lon);

class NavRoute {
  final List<NavLatLon> geometry;
  final List<NavStep> steps;
  final double distanceMeters;
  final double durationSeconds;

  /// Cumulative distance along [geometry] to each vertex.
  final List<double> along;

  /// The [geometry] vertex each step's maneuver sits on.
  final List<int> stepVertex;

  NavRoute({
    required this.geometry,
    required this.steps,
    required this.distanceMeters,
    required this.durationSeconds,
  })  : along = _cumulative(geometry),
        stepVertex = [for (final s in steps) _nearestVertex(geometry, (s.latitude, s.longitude)).$1];

  static List<double> _cumulative(List<NavLatLon> g) {
    final out = List<double>.filled(g.length, 0);
    for (var i = 1; i < g.length; i++) {
      out[i] = out[i - 1] + _dist(g[i - 1], g[i]);
    }
    return out;
  }

  /// Parses an OSRM `/route/v1` response (overview=full,
  /// geometries=geojson, steps=true). Null when OSRM found no route.
  static NavRoute? fromOsrmJson(Map<String, dynamic> json) {
    if (json['code'] != 'Ok') return null;
    final routes = json['routes'] as List;
    if (routes.isEmpty) return null;
    final route = routes.first as Map<String, dynamic>;
    final coordinates = (route['geometry'] as Map<String, dynamic>)['coordinates'] as List;
    final steps = <NavStep>[
      for (final leg in route['legs'] as List)
        for (final step in (leg as Map<String, dynamic>)['steps'] as List)
          NavStep.fromOsrm(step as Map<String, dynamic>),
    ];
    return NavRoute(
      // GeoJSON is [lon, lat].
      geometry: [
        for (final c in coordinates) (((c as List)[1] as num).toDouble(), (c[0] as num).toDouble()),
      ],
      steps: steps,
      distanceMeters: (route['distance'] as num).toDouble(),
      durationSeconds: (route['duration'] as num).toDouble(),
    );
  }
}

/// Fetches a route from the public OSRM demo server — the same "free,
/// no API key, fine at this app's scale, not for heavy production
/// traffic" posture as the OpenStreetMap tiles and the Overpass camera
/// lookups. Self-hosters can point [baseUrl] at their own OSRM instance.
/// Null on any network/parse failure; navigation then just shows a
/// straight-line bearing and distance instead.
Future<NavRoute?> fetchRoute({
  required NavLatLon from,
  required NavLatLon to,
  String baseUrl = 'https://router.project-osrm.org',
  Duration timeout = const Duration(seconds: 10),
}) async {
  final uri = Uri.parse(
    '$baseUrl/route/v1/driving/${from.$2},${from.$1};${to.$2},${to.$1}'
    '?overview=full&geometries=geojson&steps=true',
  );
  final client = HttpClient()..userAgent = 'OpenTrip (open-source ride tracker)';
  try {
    final request = await client.getUrl(uri).timeout(timeout);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) return null;
    final body = await response.transform(utf8.decoder).join().timeout(timeout);
    return NavRoute.fromOsrmJson(jsonDecode(body) as Map<String, dynamic>);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Where the rider is relative to a route: the index of the next step to
/// announce, how far away that maneuver is, and how far the rider is
/// from the route line at all (for off-route detection).
class NavProgress {
  final int nextStepIndex;
  final double metersToNextStep;
  final double metersOffRoute;
  final double metersRemaining;

  const NavProgress({
    required this.nextStepIndex,
    required this.metersToNextStep,
    required this.metersOffRoute,
    required this.metersRemaining,
  });
}

double _dist(NavLatLon a, NavLatLon b) => haversineMeters(lat1: a.$1, lon1: a.$2, lat2: b.$1, lon2: b.$2);

(int, double) _nearestVertex(List<NavLatLon> g, NavLatLon p) {
  var best = 0;
  var bestMeters = double.infinity;
  for (var i = 0; i < g.length; i++) {
    final m = _dist(g[i], p);
    if (m < bestMeters) {
      bestMeters = m;
      best = i;
    }
  }
  return (best, bestMeters);
}

/// Snaps [position] to the nearest route vertex, then picks the first
/// step whose maneuver lies ahead of that vertex along the route.
/// Vertex-based rather than true segment projection — OSRM's full
/// geometry is dense enough (a vertex every few to few dozen meters)
/// that the difference is below GPS noise.
NavProgress navProgress(NavRoute route, NavLatLon position) {
  final g = route.geometry;
  if (g.isEmpty || route.steps.isEmpty) {
    return const NavProgress(nextStepIndex: 0, metersToNextStep: 0, metersOffRoute: 0, metersRemaining: 0);
  }
  final (nearest, offRoute) = _nearestVertex(g, position);

  // The last step ("arrive") is the fallback once every turn is behind us.
  var next = route.steps.length - 1;
  for (var i = 0; i < route.steps.length; i++) {
    // "depart" is where the route started, never the next thing to do.
    if (route.steps[i].type == 'depart') continue;
    if (route.stepVertex[i] > nearest) {
      next = i;
      break;
    }
  }
  final along = route.along;
  return NavProgress(
    nextStepIndex: next,
    metersToNextStep: (along[route.stepVertex[next]] - along[nearest]).clamp(0.0, double.infinity) + offRoute,
    metersOffRoute: offRoute,
    metersRemaining: along.last - along[nearest] + offRoute,
  );
}
