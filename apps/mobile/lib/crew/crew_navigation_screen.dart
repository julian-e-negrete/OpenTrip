import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';
import '../theme/dark_tile_layer.dart';
import '../theme/ph_icons.dart';
import '../trip/geo_math.dart';
import 'crew_models.dart';
import 'crew_service.dart';
import 'nav_route.dart';

/// Turn-by-turn directions to a crewmate who's sharing their live
/// position. The destination moves, so the route is refetched whenever
/// the rider strays from it or the crewmate has moved well away from
/// where it ends — rate-limited so a long ride doesn't hammer the public
/// routing server (see nav_route.dart's fetchRoute).
///
/// Safety: like the rest of the app, this is meant to be glanced at on a
/// mounted phone, never handled while moving — the instruction banner
/// is big and high-contrast so one glance is enough.
class CrewNavigationScreen extends StatefulWidget {
  const CrewNavigationScreen({super.key, required this.target});

  final CrewLivePosition target;

  @override
  State<CrewNavigationScreen> createState() => _CrewNavigationScreenState();
}

class _CrewNavigationScreenState extends State<CrewNavigationScreen> {
  static const _offRouteMeters = 60.0;
  static const _targetDriftMeters = 150.0;
  static const _minRerouteGap = Duration(seconds: 15);

  final _mapController = MapController();
  StreamSubscription<Position>? _positionSub;
  late CrewLivePosition _target = widget.target;
  NavLatLon? _me;
  double? _myHeading;
  NavRoute? _route;
  NavProgress? _progress;
  bool _fetching = false;
  bool _routeFailed = false;
  DateTime? _lastFetchAt;
  bool _followMe = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    CrewService.instance.acquireLiveFeed();
    CrewService.instance.liveCrew.addListener(_onCrewUpdate);
    _startLocation();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    CrewService.instance.liveCrew.removeListener(_onCrewUpdate);
    CrewService.instance.releaseLiveFeed();
    super.dispose();
  }

  void _onCrewUpdate() {
    for (final p in CrewService.instance.liveCrew.value) {
      if (p.userId == _target.userId) {
        setState(() => _target = p);
        _maybeReroute();
        return;
      }
    }
  }

  Future<void> _startLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _error = 'Location permission is needed for directions.');
        return;
      }
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 5),
      ).listen(_onPosition);
    } catch (e) {
      setState(() => _error = 'Couldn\'t get your location: $e');
    }
  }

  void _onPosition(Position pos) {
    final me = (pos.latitude, pos.longitude);
    final route = _route;
    setState(() {
      _me = me;
      if (pos.heading >= 0 && pos.speed > 1) _myHeading = pos.heading;
      _progress = route == null ? null : navProgress(route, me);
    });
    if (_followMe) _mapController.move(LatLng(me.$1, me.$2), _mapController.camera.zoom);
    _maybeReroute();
  }

  NavLatLon get _targetLatLon => (_target.latitude, _target.longitude);

  void _maybeReroute() {
    final me = _me;
    if (me == null || _fetching) return;
    final route = _route;
    final last = _lastFetchAt;
    final rateLimited = last != null && DateTime.now().difference(last) < _minRerouteGap;
    if (route == null) {
      if (!rateLimited) _fetch();
      return;
    }
    if (rateLimited) return;
    final offRoute = (_progress?.metersOffRoute ?? 0) > _offRouteMeters;
    final end = route.geometry.last;
    final targetDrift = haversineMeters(lat1: end.$1, lon1: end.$2, lat2: _target.latitude, lon2: _target.longitude);
    if (offRoute || targetDrift > _targetDriftMeters) _fetch();
  }

  Future<void> _fetch() async {
    final me = _me;
    if (me == null) return;
    _fetching = true;
    _lastFetchAt = DateTime.now();
    final route = await fetchRoute(from: me, to: _targetLatLon);
    _fetching = false;
    if (!mounted) return;
    setState(() {
      if (route != null) {
        _route = route;
        _routeFailed = false;
        _progress = navProgress(route, _me ?? me);
      } else {
        _routeFailed = true;
      }
    });
  }

  String _fmtDistance(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(meters >= 10000 ? 0 : 1)} km';
    if (meters >= 100) return '${(meters / 50).round() * 50} m';
    return '${(meters / 10).round() * 10} m';
  }

  IconData _iconFor(NavStep step) {
    final m = step.modifier ?? '';
    if (step.type == 'arrive') return Ph.flagCheckered;
    if (step.type.contains('roundabout') || step.type == 'rotary') return Ph.arrowsClockwise;
    if (m == 'uturn') return Ph.arrowUUpLeft;
    if (m == 'sharp left') return Ph.arrowElbowUpLeft;
    if (m == 'sharp right') return Ph.arrowElbowUpRight;
    if (m.contains('left')) return Ph.arrowBendUpLeft;
    if (m.contains('right')) return Ph.arrowBendUpRight;
    return Ph.arrowUp;
  }

  /// Compass direction to the crewmate, for the no-route fallback.
  String _bearingLabel(NavLatLon from, NavLatLon to) {
    final lat1 = from.$1 * math.pi / 180, lat2 = to.$1 * math.pi / 180;
    final dLon = (to.$2 - from.$2) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final deg = (math.atan2(y, x) * 180 / math.pi + 360) % 360;
    const names = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return names[((deg + 22.5) ~/ 45) % 8];
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final route = _route;
    final progress = _progress;
    final target = LatLng(_target.latitude, _target.longitude);
    final stale = DateTime.now().difference(_target.updatedAt) > const Duration(seconds: 45);

    final Widget banner;
    if (_error != null) {
      banner = _Banner(icon: Ph.warning, title: _error!, subtitle: null);
    } else if (me == null) {
      banner = const _Banner(icon: Ph.crosshair, title: 'Finding your location…', subtitle: null);
    } else if (route != null && progress != null) {
      final step = route.steps[progress.nextStepIndex];
      banner = _Banner(
        icon: _iconFor(step),
        title: _fmtDistance(progress.metersToNextStep),
        subtitle: step.instruction,
      );
    } else {
      final straight = haversineMeters(lat1: me.$1, lon1: me.$2, lat2: target.latitude, lon2: target.longitude);
      banner = _Banner(
        icon: Ph.navigationArrow,
        title: '${_fmtDistance(straight)} ${_bearingLabel(me, _targetLatLon)}',
        subtitle: _routeFailed ? 'Couldn\'t get directions — showing straight-line distance' : 'Getting directions…',
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: me == null ? target : LatLng(me.$1, me.$2),
              initialZoom: 16,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              onPositionChanged: (_, hasGesture) {
                if (hasGesture && _followMe) setState(() => _followMe = false);
              },
            ),
            children: [
              const DarkTileLayer(),
              if (route != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [for (final p in route.geometry) LatLng(p.$1, p.$2)],
                      strokeWidth: 12,
                      color: Noct.accent.withValues(alpha: 0.2),
                    ),
                    Polyline(
                      points: [for (final p in route.geometry) LatLng(p.$1, p.$2)],
                      strokeWidth: 5,
                      color: Noct.a400,
                      strokeCap: StrokeCap.round,
                      strokeJoin: StrokeJoin.round,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: target,
                    width: 120,
                    height: 54,
                    child: CrewMarker(name: _target.displayName, speedKph: _target.speedKph, stale: stale),
                  ),
                  if (me != null)
                    Marker(
                      point: LatLng(me.$1, me.$2),
                      width: 26,
                      height: 26,
                      child: Transform.rotate(
                        angle: (_myHeading ?? 0) * math.pi / 180,
                        child: Icon(
                          _myHeading == null ? Ph.crosshair : Ph.navigationArrow,
                          size: 24,
                          color: Noct.a200,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 10,
            left: 12,
            right: 12,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RoundButton(icon: Ph.arrowLeft, onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 10),
                Expanded(child: banner),
              ],
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: MediaQuery.paddingOf(context).bottom + 14,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
              decoration: BoxDecoration(
                color: Noct.bg.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(Noct.rLg),
                border: Border.all(color: Noct.divider),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _target.displayName,
                          style: const TextStyle(fontSize: 15, color: Noct.text, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (route != null && progress != null) _fmtDistance(progress.metersRemaining),
                            if (route != null && progress != null && route.distanceMeters > 0)
                              '~${(route.durationSeconds * progress.metersRemaining / route.distanceMeters / 60).ceil()} min',
                            if (_target.speedKph != null) 'riding ${_target.speedKph!.toStringAsFixed(0)} km/h',
                            if (stale) 'last seen ${DateTime.now().difference(_target.updatedAt).inSeconds}s ago',
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12, color: Noct.n400),
                        ),
                      ],
                    ),
                  ),
                  if (!_followMe)
                    _RoundButton(
                      icon: Ph.crosshair,
                      onTap: () {
                        setState(() => _followMe = true);
                        if (me != null) _mapController.move(LatLng(me.$1, me.$2), 16);
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Noct.a900.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(Noct.rLg),
        border: Border.all(color: Noct.a700),
      ),
      child: Row(
        children: [
          Icon(icon, size: 34, color: Noct.a200),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Noct.stat(24)),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, color: Noct.a200),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Noct.bg.withValues(alpha: 0.92),
      shape: const CircleBorder(side: BorderSide(color: Noct.divider)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 42, height: 42, child: Icon(icon, size: 18, color: Noct.text)),
      ),
    );
  }
}

/// A crewmate on a map: their initial in a dot, with a name/speed tag
/// underneath. Shared by the Record map, the crew map and navigation.
class CrewMarker extends StatelessWidget {
  const CrewMarker({super.key, required this.name, this.speedKph, this.leanDeg, this.stale = false});

  final String name;
  final double? speedKph;
  final double? leanDeg;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final color = stale ? Noct.n600 : const Color(0xFF4FC08D);
    final details = [
      if (speedKph != null) '${speedKph!.toStringAsFixed(0)} km/h',
      if (leanDeg != null) '${leanDeg!.toStringAsFixed(0)}°',
    ].join(' · ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Noct.canvas, width: 2),
          ),
          child: Text(
            name.isEmpty ? '?' : name[0].toUpperCase(),
            style: const TextStyle(fontSize: 11, color: Noct.canvas, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration:
              BoxDecoration(color: Noct.bg.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(Noct.rSm)),
          child: Text(
            details.isEmpty ? name : '$name · $details',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: Noct.text),
          ),
        ),
      ],
    );
  }
}
