import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/models/trip.dart';
import '../data/models/trip_music_event.dart';
import '../data/models/trip_point.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/trip_repository.dart';
import '../theme/app_theme.dart';
import '../theme/date_fmt.dart';
import '../theme/layout_prefs.dart';
import '../theme/ph_icons.dart';
import '../theme/primitives.dart';
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
  List<TripMusicEvent>? _musicEvents;

  @override
  void initState() {
    super.initState();
    _loadPoints();
    _loadMusicEvents();
  }

  Future<void> _loadPoints() async {
    // TripRepository.pointsForTrip falls back to a remote pull if this
    // trip has no local points yet (e.g. it arrived via cloud sync from
    // another device) — see sync/sync_service.dart.
    final points = await TripRepository.instance.pointsForTrip(widget.trip.id);
    if (mounted) setState(() => _points = points);
  }

  Future<void> _loadMusicEvents() async {
    final events = await TripRepository.instance.musicEventsForTrip(widget.trip.id);
    if (mounted) setState(() => _musicEvents = events);
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

  void _share() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StatCardScreen(trip: widget.trip, vehicle: widget.vehicle)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    return ListenableBuilder(
      listenable: LayoutPrefs.instance,
      builder: (context, _) {
        return Scaffold(
          body: ListView(
            padding: EdgeInsets.zero,
            children: [
              SizedBox(
                height: 320,
                child: _HeroMap(
                  points: _points,
                  onBack: () => Navigator.of(context).pop(),
                  onShare: _share,
                  onDelete: _confirmDelete,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                child: _Headline(trip: trip, vehicle: widget.vehicle),
              ),
              if (LayoutPrefs.instance.tripDetail == TripDetailVariant.grid)
                _StatGrid(trip: trip)
              else
                _StatReport(trip: trip),
              if (_musicEvents != null && _musicEvents!.isNotEmpty)
                _Soundtrack(events: _musicEvents!, tripStartedAt: trip.startedAt),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.trip, required this.vehicle});
  final Trip trip;
  final Vehicle? vehicle;

  @override
  Widget build(BuildContext context) {
    final kicker = [fmtWeekdayDayMonth(trip.startedAt), if (vehicle != null) vehicle!.name].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kicker.toUpperCase(),
          style: const TextStyle(fontSize: 10, letterSpacing: 1.2, color: Noct.n500, fontWeight: FontWeight.w400),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: trip.distanceKm.toStringAsFixed(1), style: Noct.stat(56)),
              TextSpan(
                text: ' km in ${_fmtDuration(trip.durationSeconds)}',
                style: const TextStyle(fontSize: 14, color: Noct.n400, fontWeight: FontWeight.w400),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _fmtDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}

/// Variant A — the default: six stat panels in a 2-column grid. Design
/// handoff §2.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final leanDeg = trip.bleMaxLeanDeg ?? trip.phoneLeanMaxDeg;
    final waterRange = trip.bleMinWaterTemperatureC != null && trip.bleMaxWaterTemperatureC != null
        ? '${trip.bleMinWaterTemperatureC}–${trip.bleMaxWaterTemperatureC}°'
        : null;
    final cells = [
      ('Avg km/h', trip.avgSpeedKph?.toStringAsFixed(0), null),
      ('Max km/h', trip.maxSpeedKph?.toStringAsFixed(0), null),
      ('Max lean', leanDeg == null ? null : '${leanDeg.toStringAsFixed(0)}°', Noct.a300),
      ('Max rpm', trip.bleMaxRpm?.toString(), null),
      ('Hardest brake', trip.behaviorMaxBrakeG == null ? null : '${trip.behaviorMaxBrakeG!.toStringAsFixed(2)}g', null),
      ('Water temp', waterRange, null),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 9,
        crossAxisSpacing: 9,
        childAspectRatio: 1.7,
        children: [
          for (final (label, value, color) in cells)
            NoctPanel(child: NoctStat(value: value ?? '—', label: label, valueSize: 24, valueColor: color)),
        ],
      ),
    );
  }
}

/// Variant B — grouped label/value rows, no panels. Design handoff §2.
class _StatReport extends StatelessWidget {
  const _StatReport({required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final ride = [
      ('Average speed', trip.avgSpeedKph == null ? null : '${trip.avgSpeedKph!.toStringAsFixed(0)} km/h'),
      ('Max speed', trip.maxSpeedKph == null ? null : '${trip.maxSpeedKph!.toStringAsFixed(0)} km/h'),
      ('GPS points', '${trip.pointCount}'),
    ];
    final bike = [
      ('Max rpm', trip.bleMaxRpm?.toString()),
      ('Max lean angle', trip.bleMaxLeanDeg == null ? null : '${trip.bleMaxLeanDeg!.toStringAsFixed(0)}°'),
      (
        'Water temperature',
        trip.bleMinWaterTemperatureC == null || trip.bleMaxWaterTemperatureC == null
            ? null
            : '${trip.bleMinWaterTemperatureC}–${trip.bleMaxWaterTemperatureC} °C',
      ),
      ('Odometer at end', trip.bleOdometerKm == null ? null : '${trip.bleOdometerKm!.toStringAsFixed(0)} km'),
    ];
    final behavior = [
      (
        'Hardest braking',
        trip.behaviorMaxBrakeG == null ? null : '${trip.behaviorMaxBrakeG!.toStringAsFixed(2)}g',
      ),
      (
        'Hardest cornering',
        trip.behaviorMaxCorneringG == null ? null : '${trip.behaviorMaxCorneringG!.toStringAsFixed(2)}g',
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Group('From the ride', ride),
          _Group('From the bike', bike),
          _Group('Behaviour', behavior),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.rows);
  final String title;
  final List<(String, String?)> rows;

  @override
  Widget build(BuildContext context) {
    final populated = rows.where((r) => r.$2 != null).toList();
    if (populated.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 4),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(fontSize: 10, letterSpacing: 1.2, color: Noct.accent, fontWeight: FontWeight.w400),
          ),
        ),
        for (final (label, value) in populated)
          Container(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Noct.n900, width: 1))),
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontSize: 13, color: Noct.n400, fontWeight: FontWeight.w400)),
                Text(
                  value!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()],
                    color: Noct.text,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Soundtrack extends StatelessWidget {
  const _Soundtrack({required this.events, required this.tripStartedAt});
  final List<TripMusicEvent> events;
  final DateTime tripStartedAt;

  String _fmtOffset(Duration d) {
    final clamped = d.isNegative ? Duration.zero : d;
    final hours = clamped.inHours;
    final minutes = clamped.inMinutes % 60;
    return hours > 0 ? '${hours}h ${minutes}m in' : '${clamped.inMinutes}m in';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SOUNDTRACK',
            style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: Noct.n500, fontWeight: FontWeight.w400),
          ),
          const SizedBox(height: 11),
          for (final event in events)
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Row(
                children: [
                  const Icon(Ph.musicNoteFill, size: 14, color: Noct.a400),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.track,
                          style: const TextStyle(fontSize: 13, color: Noct.text, fontWeight: FontWeight.w400),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (event.artist != null)
                          Text(
                            event.artist!,
                            style: const TextStyle(fontSize: 11, color: Noct.n500, fontWeight: FontWeight.w400),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _fmtOffset(event.startedAt.difference(tripStartedAt)),
                    style: const TextStyle(fontSize: 11, color: Noct.n600, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Full-bleed replay map: real tiles (street or satellite, toggled via
/// the layer chip), a doubled route stroke, a scrim so the floating
/// controls read over any tile imagery, and a scrubber that paces the
/// marker by the trip's real elapsed time (see route_replay.dart), not
/// point index — a stretch idled at a light plays slower than the open
/// road at any speed setting.
class _HeroMap extends StatefulWidget {
  const _HeroMap({required this.points, required this.onBack, required this.onShare, required this.onDelete});

  final List<TripPoint>? points;
  final VoidCallback onBack;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  State<_HeroMap> createState() => _HeroMapState();
}

class _HeroMapState extends State<_HeroMap> with SingleTickerProviderStateMixin {
  static const _baseDuration = Duration(seconds: 18);

  late final AnimationController _controller;
  bool _satellite = false;
  bool _doubleSpeed = false;

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

  void _toggleSpeed() {
    setState(() => _doubleSpeed = !_doubleSpeed);
    _controller.duration = Duration(
      milliseconds: _baseDuration.inMilliseconds ~/ (_doubleSpeed ? 2 : 1),
    );
    if (_controller.isAnimating) _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
    if (pts == null) {
      return const ColoredBox(color: Noct.canvas, child: Center(child: CircularProgressIndicator()));
    }
    if (pts.isEmpty) {
      return const ColoredBox(
        color: Noct.canvas,
        child: Center(child: Text('No route recorded for this trip.', style: TextStyle(color: Noct.n500))),
      );
    }

    final routePoints = pts.map((p) => LatLng(p.latitude, p.longitude)).toList();
    final bounds = LatLngBounds.fromPoints(routePoints);

    return ColoredBox(
      color: Noct.canvas,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final traveled = pts.length < 2 ? pts.length : pointCountAtProgress(pts, _controller.value);
          final (curLat, curLon) = positionAtProgress(pts, _controller.value);
          final current = LatLng(curLat, curLon);
          final traveledPoints = [...routePoints.take(traveled), current];
          final hudPoint = pts[(traveled - 1).clamp(0, pts.length - 1)];

          return Stack(
            fit: StackFit.expand,
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCameraFit: CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(32)),
                ),
                children: [
                  TileLayer(
                    // Dark Matter, not OSM's colorful default street
                    // style — matches territory_map_screen.dart, the only
                    // other place this app tiles a street basemap.
                    // Satellite imagery is exempt (a photograph can't be
                    // made to match an app palette); only the street mode
                    // needs to.
                    urlTemplate: _satellite
                        ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                        : 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                    userAgentPackageName: 'co.opentrip.opentrip_mobile',
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(points: routePoints, strokeWidth: 12, color: Noct.accent.withValues(alpha: 0.18)),
                      Polyline(
                        points: traveledPoints,
                        strokeWidth: 3,
                        color: Noct.accent,
                        strokeCap: StrokeCap.round,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: routePoints.first,
                        width: 5.5,
                        height: 5.5,
                        child: const DecoratedBox(decoration: BoxDecoration(color: Noct.n200, shape: BoxShape.circle)),
                      ),
                      Marker(
                        point: routePoints.last,
                        width: 5.5,
                        height: 5.5,
                        child: const DecoratedBox(decoration: BoxDecoration(color: Noct.a200, shape: BoxShape.circle)),
                      ),
                    ],
                  ),
                ],
              ),
              // Scrim: lets the floating chips and capsule read over any
              // tile imagery underneath.
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Noct.bg.withValues(alpha: 0.90),
                        Colors.transparent,
                        Colors.transparent,
                        Noct.bg,
                      ],
                      stops: const [0.0, 0.30, 0.55, 0.99],
                    ),
                  ),
                ),
              ),
              Positioned(
                // The hero map is deliberately full-bleed under the status
                // bar/notch, but these chips have to be real tap targets —
                // without the safe-area inset they render (and hit-test)
                // right under the system status bar, unreachable.
                top: 12 + MediaQuery.paddingOf(context).top,
                left: 10,
                right: 10,
                child: Row(
                  children: [
                    _MapChip(icon: Ph.arrowLeft, onTap: widget.onBack),
                    const Spacer(),
                    _MapChip(icon: Ph.export_, onTap: widget.onShare),
                    const SizedBox(width: 8),
                    _MapChip(icon: Ph.trash, onTap: widget.onDelete),
                  ],
                ),
              ),
              Positioned(
                left: 14,
                bottom: 64,
                child: _TelemetryCapsule(point: hudPoint),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 18,
                child: _Scrubber(
                  controller: _controller,
                  doubleSpeed: _doubleSpeed,
                  satellite: _satellite,
                  onTogglePlay: _togglePlay,
                  onToggleSpeed: _toggleSpeed,
                  onToggleLayer: () => setState(() => _satellite = !_satellite),
                  onScrub: (v) {
                    _controller.stop();
                    setState(() => _controller.value = v);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MapChip extends StatelessWidget {
  const _MapChip({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Material(
        color: Noct.bg.withValues(alpha: 0.60),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(icon, size: 19, color: Noct.text),
          ),
        ),
      ),
    );
  }
}

class _TelemetryCapsule extends StatelessWidget {
  const _TelemetryCapsule({required this.point});
  final TripPoint point;

  @override
  Widget build(BuildContext context) {
    final speed = point.bleSpeedKph ?? point.speedKph;
    final columns = [
      ('km/h', speed?.toStringAsFixed(0), null),
      ('rpm', point.bleRpm?.toString(), null),
      ('gear', point.bleGear?.toString(), null),
      ('lean', point.bleLeanDeg == null ? null : '${point.bleLeanDeg!.toStringAsFixed(0)}°', Noct.a300),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Noct.canvas.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(Noct.rMd),
        border: Border.all(color: Noct.n800, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < columns.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  columns[i].$2 ?? '—',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: columns[i].$3 ?? Noct.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  columns[i].$1.toUpperCase(),
                  style: const TextStyle(fontSize: 9, letterSpacing: 0.9, color: Noct.n500, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Scrubber extends StatelessWidget {
  const _Scrubber({
    required this.controller,
    required this.doubleSpeed,
    required this.satellite,
    required this.onTogglePlay,
    required this.onToggleSpeed,
    required this.onToggleLayer,
    required this.onScrub,
  });

  final AnimationController controller;
  final bool doubleSpeed;
  final bool satellite;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleSpeed;
  final VoidCallback onToggleLayer;
  final ValueChanged<double> onScrub;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onTogglePlay,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Noct.accent.withValues(alpha: 0.10),
              border: Border.all(color: Noct.accent, width: 1.5),
            ),
            child: Icon(controller.isAnimating ? Ph.pauseFill : Ph.playFill, size: 14, color: Noct.a200),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: Noct.accent,
              inactiveTrackColor: Noct.n800,
              thumbColor: Noct.a200,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(value: controller.value.clamp(0.0, 1.0), onChanged: onScrub),
          ),
        ),
        GestureDetector(
          onTap: onToggleSpeed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              doubleSpeed ? '2×' : '1×',
              style: const TextStyle(fontSize: 11, color: Noct.n400, fontWeight: FontWeight.w400),
            ),
          ),
        ),
        GestureDetector(
          onTap: onToggleLayer,
          child: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(Ph.globeHemisphereWest, size: 16, color: satellite ? Noct.accent : Noct.n400),
          ),
        ),
      ],
    );
  }
}
