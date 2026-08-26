import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/models/trip.dart';
import '../data/models/trip_point.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/trip_repository.dart';
import '../trip/route_replay.dart';
import 'stat_card_screen.dart';

class TripDetailScreen extends StatefulWidget {
  const TripDetailScreen({super.key, required this.trip, required this.vehicle});

  final Trip trip;
  final Vehicle? vehicle;

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  List<TripPoint>? _points;

  @override
  void initState() {
    super.initState();
    _loadPoints();
  }

  Future<void> _loadPoints() async {
    // TripRepository.pointsForTrip falls back to a remote pull if this
    // trip has no local points yet (e.g. it arrived via cloud sync from
    // another device) — see sync/sync_service.dart.
    final points = await TripRepository.instance.pointsForTrip(widget.trip.id);
    if (mounted) setState(() => _points = points);
  }

  String _fmtDuration(int seconds) {
    final d = Duration(seconds: seconds);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete trip?'),
        content: Text('This ${widget.trip.distanceKm.toStringAsFixed(2)} km trip will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await TripRepository.instance.deleteTrip(widget.trip.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.vehicle?.name ?? 'Trip'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => StatCardScreen(trip: trip, vehicle: widget.vehicle)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete trip',
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(height: 260, child: _RouteMap(points: _points)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _HeroStats(distanceKm: trip.distanceKm, durationLabel: _fmtDuration(trip.durationSeconds)),
                const SizedBox(height: 20),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.9,
                  children: [
                    _StatCard(
                      'Avg speed',
                      trip.avgSpeedKph == null ? '—' : '${trip.avgSpeedKph!.toStringAsFixed(0)} km/h',
                      scheme.primary,
                    ),
                    _StatCard(
                      'Max speed',
                      trip.maxSpeedKph == null ? '—' : '${trip.maxSpeedKph!.toStringAsFixed(0)} km/h',
                      scheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _Row('Started', trip.startedAt.toLocal().toString().substring(0, 19)),
                if (trip.endedAt != null) _Row('Ended', trip.endedAt!.toLocal().toString().substring(0, 19)),
                _Row('GPS points recorded', '${trip.pointCount}'),
                if (trip.hasBleTelemetry) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 4),
                    child: Text(
                      'From the bike',
                      style: TextStyle(color: scheme.secondary, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                    ),
                  ),
                  if (trip.bleMaxSpeedKph != null)
                    _Row('Max speed (bike)', '${trip.bleMaxSpeedKph!.toStringAsFixed(0)} km/h'),
                  if (trip.bleMaxRpm != null) _Row('Max RPM', '${trip.bleMaxRpm}'),
                  if (trip.bleMaxLeanDeg != null)
                    _Row('Max lean angle', '${trip.bleMaxLeanDeg!.toStringAsFixed(0)}°'),
                  if (trip.bleMaxBrakePressureKpa != null)
                    _Row('Max front brake pressure', '${trip.bleMaxBrakePressureKpa!.toStringAsFixed(0)} kPa'),
                  if (trip.bleMinWaterTemperatureC != null && trip.bleMaxWaterTemperatureC != null)
                    _Row(
                      'Water temperature range',
                      '${trip.bleMinWaterTemperatureC}–${trip.bleMaxWaterTemperatureC} °C',
                    ),
                  if (trip.bleOdometerKm != null)
                    _Row('Odometer at end of trip', '${trip.bleOdometerKm!.toStringAsFixed(0)} km'),
                ],
                if (trip.hasBehaviorStats) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 4),
                    child: Text(
                      'Driving behavior',
                      style: TextStyle(color: scheme.tertiary, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                    ),
                  ),
                  if (trip.behaviorMaxAccelG != null)
                    _Row(
                      'Hardest acceleration',
                      '${trip.behaviorMaxAccelG!.toStringAsFixed(2)}g'
                      '${trip.behaviorHardAccelCount == null ? '' : ' · ${trip.behaviorHardAccelCount} hard'}',
                    ),
                  if (trip.behaviorMaxBrakeG != null)
                    _Row(
                      'Hardest braking',
                      '${trip.behaviorMaxBrakeG!.toStringAsFixed(2)}g'
                      '${trip.behaviorHardBrakeCount == null ? '' : ' · ${trip.behaviorHardBrakeCount} hard'}',
                    ),
                  if (trip.behaviorMaxCorneringG != null)
                    _Row(
                      'Hardest cornering',
                      '${trip.behaviorMaxCorneringG!.toStringAsFixed(2)}g'
                      '${trip.behaviorHardCorneringCount == null ? '' : ' · ${trip.behaviorHardCorneringCount} hard'}',
                    ),
                  if (trip.phoneLeanMaxDeg != null)
                    _Row('Max lean angle (phone)', '${trip.phoneLeanMaxDeg!.toStringAsFixed(0)}°'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStats extends StatelessWidget {
  const _HeroStats({required this.distanceKm, required this.durationLabel});
  final double distanceKm;
  final String durationLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Column(
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: distanceKm.toStringAsFixed(2),
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          color: scheme.secondary,
                        ),
                      ),
                      TextSpan(
                        text: ' km',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Text(
                  'DISTANCE',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            Container(width: 1, height: 40, color: scheme.outlineVariant),
            Column(
              children: [
                Text(
                  durationLabel,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: scheme.onSurface),
                ),
                Text(
                  'DURATION',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.label, this.value, this.valueColor);
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: valueColor)),
            Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// Route polyline (or an animated replay, see [_playing]) over either
/// OpenStreetMap street tiles or Esri's public World Imagery satellite
/// tiles — the street server (tile.openstreetmap.org) is fine for this
/// app's current scale but comes with OSM's tile usage policy (low
/// volume, no heavy production traffic); the satellite one
/// (server.arcgisonline.com) is Esri's community-shared service, used
/// the same way here — no API key, fine at this scale, not meant for
/// heavy/production traffic, attribution shown. Self-hosting either or
/// switching to a paid provider is the documented upgrade path if that
/// ever becomes a real concern. See docs/ROADMAP.md.
///
/// Replay pace defaults to [_baseDuration] regardless of how long the
/// actual trip was — an hours-long drive played back in real time
/// wouldn't be watched by anyone — but the speed chip (1×/2×/4×/8×) lets
/// it go faster still. [positionAtProgress] paces the *marker* by the
/// trip's real elapsed time within that window (see
/// trip/route_replay.dart), so a stretch where you idled at a light
/// plays slower than the open road, not identically fast, at any speed
/// setting. While the marker is moving (or paused partway through), a
/// small instrument HUD reads live speed and — if this trip has any BLE
/// telemetry (trip/recording_screen.dart samples it onto each GPS point
/// as it's recorded, see data/models/trip_point.dart) — RPM, gear, and
/// lean off whichever point the marker has most recently reached, the
/// same way route_replay.dart already picks the "traveled so far" prefix
/// for the trailing polyline.
class _RouteMap extends StatefulWidget {
  const _RouteMap({required this.points});
  final List<TripPoint>? points;

  @override
  State<_RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<_RouteMap> with SingleTickerProviderStateMixin {
  static const _baseDuration = Duration(seconds: 18);
  static const _speedOptions = [1, 2, 4, 8];

  late final AnimationController _controller;
  bool _satellite = false;
  int _speedIndex = 0;

  int get _speedMultiplier => _speedOptions[_speedIndex];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _baseDuration);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_controller.isAnimating) {
      _controller.stop();
    } else {
      if (_controller.isCompleted) _controller.value = 0;
      _controller.forward();
    }
    setState(() {});
  }

  void _cycleSpeed() {
    setState(() => _speedIndex = (_speedIndex + 1) % _speedOptions.length);
    // AnimationController.duration is only consulted when forward()/
    // reverse() actually (re)starts the simulation — mutating it alone
    // doesn't retroactively speed up a simulation already in flight, so
    // an animating controller needs forward() called again to pick up
    // the new pace for whatever fraction is left.
    _controller.duration = Duration(milliseconds: _baseDuration.inMilliseconds ~/ _speedMultiplier);
    if (_controller.isAnimating) _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
    if (pts == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (pts.isEmpty) {
      return const ColoredBox(
        color: Color(0xFF1A1A1A),
        child: Center(child: Text('No route recorded for this trip.')),
      );
    }

    final routePoints = pts.map((p) => LatLng(p.latitude, p.longitude)).toList();
    final bounds = LatLngBounds.fromPoints(routePoints);

    return Stack(
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final traveled = pts.length < 2 ? pts.length : pointCountAtProgress(pts, _controller.value);
            final (curLat, curLon) = positionAtProgress(pts, _controller.value);
            final current = LatLng(curLat, curLon);
            final traveledPoints = [...routePoints.take(traveled), current];
            final hudPoint = pts[traveled - 1];

            return Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCameraFit: CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(32)),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _satellite
                          ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                          : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'co.opentrip.opentrip_mobile',
                    ),
                    PolylineLayer(
                      polylines: [
                        // Full route, dim — context for where the animated
                        // portion is headed while replaying.
                        Polyline(points: routePoints, strokeWidth: 3, color: Colors.white.withValues(alpha: 0.35)),
                        Polyline(
                          points: traveledPoints,
                          strokeWidth: 4,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ],
                    ),
                    // Start/end pin colors and the HUD/chips' black54
                    // background are deliberately fixed, not
                    // Theme.of(context) — they sit on top of unpredictable
                    // street/satellite tile imagery, not app chrome, and
                    // green-start/red-end is a universal map convention
                    // worth keeping recognizable regardless of the app's
                    // own accent palette.
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: routePoints.first,
                          width: 16,
                          height: 16,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
                          ),
                        ),
                        Marker(
                          point: routePoints.last,
                          width: 16,
                          height: 16,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                          ),
                        ),
                        if (_controller.isAnimating || _controller.value > 0)
                          Marker(
                            point: current,
                            width: 22,
                            height: 22,
                            child: const Icon(Icons.navigation, color: Colors.white, shadows: [
                              Shadow(color: Colors.black, blurRadius: 4),
                            ]),
                          ),
                      ],
                    ),
                  ],
                ),
                if (_controller.value > 0)
                  Positioned(top: 8, left: 8, child: _TelemetryHud(point: hudPoint)),
              ],
            );
          },
        ),
        if (pts.length >= 2)
          Positioned(
            right: 8,
            bottom: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MapChip(
                  icon: _satellite ? Icons.map_outlined : Icons.satellite_alt_outlined,
                  tooltip: _satellite ? 'Street map' : 'Satellite',
                  onPressed: () => setState(() => _satellite = !_satellite),
                ),
                const SizedBox(width: 8),
                _SpeedChip(multiplier: _speedMultiplier, onPressed: _cycleSpeed),
                const SizedBox(width: 8),
                _MapChip(
                  icon: _controller.isAnimating ? Icons.pause : Icons.play_arrow,
                  tooltip: _controller.isAnimating ? 'Pause replay' : 'Play replay',
                  onPressed: _togglePlay,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A compact instrument readout for whichever point the replay marker has
/// most recently reached — always shows GPS speed (falling back to the
/// bike's own speed reading when this trip has BLE telemetry, since a
/// bike's speedometer is more accurate at low speed than a GPS estimate),
/// plus RPM/gear/lean whenever that point happens to carry them. Renders
/// nothing for a point with no usable reading at all, rather than an
/// empty floating chip.
class _TelemetryHud extends StatelessWidget {
  const _TelemetryHud({required this.point});
  final TripPoint point;

  @override
  Widget build(BuildContext context) {
    final speed = point.bleSpeedKph ?? point.speedKph;
    final readouts = <(String, String)>[
      if (speed != null) ('SPEED', '${speed.toStringAsFixed(0)} km/h'),
      if (point.bleRpm != null) ('RPM', '${point.bleRpm}'),
      if (point.bleGear != null) ('GEAR', '${point.bleGear}'),
      if (point.bleLeanDeg != null) ('LEAN', '${point.bleLeanDeg!.toStringAsFixed(0)}°'),
    ];
    if (readouts.isEmpty) return const SizedBox.shrink();

    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < readouts.length; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    readouts[i].$2,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  Text(
                    readouts[i].$1,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MapChip extends StatelessWidget {
  const _MapChip({required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: IconButton(icon: Icon(icon, color: Colors.white), tooltip: tooltip, onPressed: onPressed),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({required this.multiplier, required this.onPressed});
  final int multiplier;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Text(
              '$multiplier×',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
