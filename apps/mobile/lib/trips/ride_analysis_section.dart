import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../data/models/trip_point.dart';
import '../theme/app_theme.dart';
import '../theme/dark_tile_layer.dart';
import '../theme/primitives.dart';
import '../trip/ride_analysis.dart';

/// Low-to-high color scale shared by the speed and lean maps — cool for
/// cruising/upright, hot for fast/deep. Saturated on purpose: unlike the
/// rest of Nocturne this is data encoding, and it has to read at a glance
/// over dark map tiles.
const _ramp = [Color(0xFF5B8DEF), Color(0xFF4FC08D), Color(0xFFF2C14E), Color(0xFFE5534B)];

Color rampColor(double level) {
  final t = level.clamp(0.0, 1.0) * (_ramp.length - 1);
  final i = t.floor().clamp(0, _ramp.length - 2);
  return Color.lerp(_ramp[i], _ramp[i + 1], t - i)!;
}

/// "Ride analysis" on trip detail: the route colored by speed or lean,
/// tap anywhere on it (or drag along the profile chart below) to read the
/// exact value at that spot, plus a list of the ride's deepest corners —
/// tap one to jump the map to it. Built purely from the trip's stored
/// points (trip/ride_analysis.dart), so it works for any trip recorded
/// with GPS; the Lean tab appears whenever the ride has lean data, from
/// the bike's IMU or the phone's "Track lean angle" mode.
class RideAnalysisSection extends StatefulWidget {
  const RideAnalysisSection({super.key, required this.points});

  final List<TripPoint> points;

  @override
  State<RideAnalysisSection> createState() => _RideAnalysisSectionState();
}

class _RideAnalysisSectionState extends State<RideAnalysisSection> {
  final _mapController = MapController();
  late RideMetric _metric;
  int? _selected;
  late List<Corner> _corners;
  late bool _hasLean;

  @override
  void initState() {
    super.initState();
    _hasLean = hasMetric(widget.points, RideMetric.lean);
    _metric = _hasLean ? RideMetric.lean : RideMetric.speed;
    _corners = _hasLean ? detectCorners(widget.points) : const [];
  }

  void _select(int? index, {bool moveMap = false}) {
    setState(() => _selected = index);
    if (moveMap && index != null) {
      final p = widget.points[index];
      _mapController.move(LatLng(p.latitude, p.longitude), 16);
    }
  }

  String _unit(RideMetric m) => m == RideMetric.speed ? 'km/h' : '°';

  String _fmt(double? v, RideMetric m) => v == null ? '—' : '${v.toStringAsFixed(0)}${m == RideMetric.speed ? ' km/h' : '°'}';

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
    if (pts.length < 2) return const SizedBox.shrink();

    final scaleMax = scaleMaxFor(pts, _metric);
    final segments = segmentRoute(pts, _metric, scaleMax: scaleMax);
    final latLngs = [for (final p in pts) LatLng(p.latitude, p.longitude)];
    final bounds = LatLngBounds.fromPoints(latLngs);
    final degenerate = (bounds.north - bounds.south).abs() < 1e-6 && (bounds.east - bounds.west).abs() < 1e-6;
    final selected = _selected;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'RIDE ANALYSIS',
                  style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: Noct.accent, fontWeight: FontWeight.w400),
                ),
              ),
              if (_hasLean)
                NoctSegmentedControl<RideMetric>(
                  options: const [(RideMetric.lean, 'Lean'), (RideMetric.speed, 'Speed')],
                  value: _metric,
                  onChanged: (m) => setState(() => _metric = m),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(Noct.rMd),
            child: SizedBox(
              height: 250,
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: degenerate ? latLngs.first : bounds.center,
                      initialZoom: 16,
                      initialCameraFit: degenerate
                          ? null
                          : CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(24)),
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                      onTap: (_, latLng) => _select(nearestPointIndex(pts, latLng.latitude, latLng.longitude)),
                    ),
                    children: [
                      const DarkTileLayer(),
                      PolylineLayer(
                        polylines: [
                          for (final s in segments)
                            Polyline(
                              points: latLngs.sublist(s.startIndex, s.endIndex + 1),
                              strokeWidth: 4,
                              color: s.level == null ? Noct.n600 : rampColor(s.level!),
                              strokeCap: StrokeCap.round,
                              strokeJoin: StrokeJoin.round,
                            ),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          if (_metric == RideMetric.lean)
                            for (var i = 0; i < _corners.length && i < 5; i++)
                              Marker(
                                point: latLngs[_corners[i].peakIndex],
                                width: 20,
                                height: 20,
                                child: GestureDetector(
                                  onTap: () => _select(_corners[i].peakIndex),
                                  child: _CornerBadge(rank: i + 1),
                                ),
                              ),
                          if (selected != null)
                            Marker(
                              point: latLngs[selected],
                              width: 16,
                              height: 16,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Noct.text,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Noct.canvas, width: 3),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: _Legend(max: scaleMax, unit: _unit(_metric)),
                  ),
                  if (selected != null)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: _Readout(
                        point: pts[selected],
                        elapsed: pts[selected].timestamp.difference(pts.first.timestamp),
                        fmt: _fmt,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ProfileChart(
            points: pts,
            metric: _metric,
            scaleMax: scaleMax,
            selected: selected,
            onSelect: (i) => _select(i),
          ),
          if (_metric == RideMetric.lean && _corners.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(top: 16, bottom: 4),
              child: Text(
                'DEEPEST CORNERS',
                style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: Noct.n500, fontWeight: FontWeight.w400),
              ),
            ),
            for (var i = 0; i < _corners.length && i < 5; i++)
              _CornerRow(
                rank: i + 1,
                corner: _corners[i],
                atElapsed: pts[_corners[i].peakIndex].timestamp.difference(pts.first.timestamp),
                selected: selected == _corners[i].peakIndex,
                onTap: () => _select(_corners[i].peakIndex, moveMap: true),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${_corners.length} corner${_corners.length == 1 ? '' : 's'} past 15° this ride',
                style: const TextStyle(fontSize: 11.5, color: Noct.n500),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _fmtElapsed(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}' : '${d.inMinutes}:${two(d.inSeconds % 60)}';
}

class _CornerBadge extends StatelessWidget {
  const _CornerBadge({required this.rank});
  final int rank;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Noct.canvas,
        shape: BoxShape.circle,
        border: Border.all(color: _ramp.last, width: 1.5),
      ),
      child: Text('$rank', style: const TextStyle(fontSize: 10, color: Noct.text, fontWeight: FontWeight.w600)),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.max, required this.unit});
  final double max;
  final String unit;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 10.5, color: Noct.n300, fontFeatures: [FontFeature.tabularFigures()]);
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Noct.bg.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(Noct.rSm)),
        child: Row(
          children: [
            Text('0 $unit', style: style),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: const LinearGradient(colors: _ramp),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('${max.toStringAsFixed(0)} $unit', style: style),
          ],
        ),
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.point, required this.elapsed, required this.fmt});
  final TripPoint point;
  final Duration elapsed;
  final String Function(double?, RideMetric) fmt;

  @override
  Widget build(BuildContext context) {
    final lean = effectiveLeanDeg(point);
    const label = TextStyle(fontSize: 9.5, color: Noct.n500, letterSpacing: 0.8);
    const value = TextStyle(fontSize: 14, color: Noct.text, fontWeight: FontWeight.w500, fontFeatures: [FontFeature.tabularFigures()]);
    Widget cell(String l, String v) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [Text(v, style: value), Text(l, style: label)],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Noct.bg.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(Noct.rMd),
        border: Border.all(color: Noct.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          cell('AT', _fmtElapsed(elapsed)),
          const SizedBox(width: 14),
          cell('SPEED', fmt(effectiveSpeedKph(point), RideMetric.speed)),
          if (lean != null) ...[const SizedBox(width: 14), cell('LEAN', fmt(lean, RideMetric.lean))],
          if (point.bleGear != null) ...[const SizedBox(width: 14), cell('GEAR', '${point.bleGear}')],
          if (point.bleRpm != null) ...[const SizedBox(width: 14), cell('RPM', '${point.bleRpm}')],
        ],
      ),
    );
  }
}

/// The metric over the ride's timeline, as a filled line — drag or tap
/// along it to move the map's selected point, so "where was that peak?"
/// is one gesture.
class _ProfileChart extends StatelessWidget {
  const _ProfileChart({
    required this.points,
    required this.metric,
    required this.scaleMax,
    required this.selected,
    required this.onSelect,
  });

  final List<TripPoint> points;
  final RideMetric metric;
  final double scaleMax;
  final int? selected;
  final ValueChanged<int> onSelect;

  int _indexAt(double dx, double width) {
    final start = points.first.timestamp;
    final totalMs = points.last.timestamp.difference(start).inMilliseconds;
    if (totalMs <= 0 || width <= 0) return 0;
    final targetMs = (dx / width).clamp(0.0, 1.0) * totalMs;
    // Points are time-ordered — binary search for the nearest.
    var lo = 0, hi = points.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (points[mid].timestamp.difference(start).inMilliseconds < targetMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => onSelect(_indexAt(d.localPosition.dx, width)),
          onHorizontalDragUpdate: (d) => onSelect(_indexAt(d.localPosition.dx, width)),
          child: SizedBox(
            height: 64,
            width: width,
            child: CustomPaint(
              painter: _ProfilePainter(points: points, metric: metric, scaleMax: scaleMax, selected: selected),
            ),
          ),
        );
      },
    );
  }
}

class _ProfilePainter extends CustomPainter {
  _ProfilePainter({required this.points, required this.metric, required this.scaleMax, required this.selected});

  final List<TripPoint> points;
  final RideMetric metric;
  final double scaleMax;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final start = points.first.timestamp;
    final totalMs = points.last.timestamp.difference(start).inMilliseconds.clamp(1, 1 << 62);
    double xOf(TripPoint p) => p.timestamp.difference(start).inMilliseconds / totalMs * size.width;
    double yOf(double v) => size.height - (v / scaleMax).clamp(0.0, 1.0) * (size.height - 4);

    final line = Path();
    var started = false;
    for (final p in points) {
      final v = metricValue(p, metric);
      if (v == null) {
        started = false;
        continue;
      }
      if (!started) {
        line.moveTo(xOf(p), yOf(v));
        started = true;
      } else {
        line.lineTo(xOf(p), yOf(v));
      }
    }

    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = Noct.surface);
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: _ramp,
        ).createShader(bounds),
    );

    final sel = selected;
    if (sel != null && sel < points.length) {
      final x = xOf(points[sel]);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), Paint()..color = Noct.n300..strokeWidth = 1);
      final v = metricValue(points[sel], metric);
      if (v != null) canvas.drawCircle(Offset(x, yOf(v)), 3.5, Paint()..color = Noct.text);
    }
  }

  @override
  bool shouldRepaint(_ProfilePainter old) =>
      old.points != points || old.metric != metric || old.selected != selected || old.scaleMax != scaleMax;
}

class _CornerRow extends StatelessWidget {
  const _CornerRow({
    required this.rank,
    required this.corner,
    required this.atElapsed,
    required this.selected,
    required this.onTap,
  });

  final int rank;
  final Corner corner;
  final Duration atElapsed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const num = TextStyle(fontSize: 13, color: Noct.text, fontFeatures: [FontFeature.tabularFigures()]);
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Noct.n900, width: 1))),
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            _CornerBadge(rank: rank),
            const SizedBox(width: 12),
            Text('${corner.peakLeanDeg.toStringAsFixed(0)}°', style: num.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                corner.apexSpeedKph == null ? 'apex speed —' : 'at ${corner.apexSpeedKph!.toStringAsFixed(0)} km/h',
                style: const TextStyle(fontSize: 12.5, color: Noct.n400),
              ),
            ),
            Text(_fmtElapsed(atElapsed), style: TextStyle(fontSize: 12, color: selected ? Noct.a200 : Noct.n500)),
          ],
        ),
      ),
    );
  }
}
