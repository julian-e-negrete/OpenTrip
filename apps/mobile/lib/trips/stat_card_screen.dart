import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models/trip.dart';
import '../data/models/trip_point.dart';
import '../data/models/vehicle.dart';
import '../theme/app_theme.dart';
import '../theme/date_fmt.dart';
import '../theme/ph_icons.dart';
import '../theme/primitives.dart';
import '../trip/ride_analysis.dart';
import '../trip/route_simplify.dart';
import 'ride_analysis_section.dart' show rampColor;

/// The card designs a rider can pick from before sharing — Classic is
/// the original numbers poster; Route draws the ride's own shape colored
/// by speed; Lean leads with max lean angle (only offered when the trip
/// has any); Story is a tall 9:16 layout sized for Instagram/WhatsApp
/// stories.
enum StatCardTemplate { classic, route, lean, story }

/// Renders a trip's key numbers as a shareable image — tap Share (or the
/// download glyph) to capture the card below (via [RepaintBoundary]) and
/// hand it to the OS share sheet, which on both Android and iOS offers a
/// "save image" option of its own — this app has no separate photo-
/// library-writing dependency, so both actions go through the same
/// capture-and-share flow rather than one silently doing less than its
/// icon implies. Purely client-side: no backend involved, nothing
/// generated or stored server-side, just a PNG written to a temp file
/// for the share sheet to read.
class StatCardScreen extends StatefulWidget {
  const StatCardScreen({super.key, required this.trip, required this.vehicle, this.points});

  final Trip trip;
  final Vehicle? vehicle;

  /// The trip's route, if already loaded — needed for the Route and
  /// Story templates, which are hidden without it.
  final List<TripPoint>? points;

  @override
  State<StatCardScreen> createState() => _StatCardScreenState();
}

class _StatCardScreenState extends State<StatCardScreen> {
  final _cardKey = GlobalKey();
  bool _sharing = false;
  StatCardTemplate _template = StatCardTemplate.classic;

  double? get _maxLeanDeg => widget.trip.bleMaxLeanDeg ?? widget.trip.phoneLeanMaxDeg;
  bool get _hasRoute => (widget.points?.length ?? 0) >= 2;

  List<StatCardTemplate> get _available => [
    StatCardTemplate.classic,
    if (_hasRoute) StatCardTemplate.route,
    if (_maxLeanDeg != null) StatCardTemplate.lean,
    if (_hasRoute) StatCardTemplate.story,
  ];

  Widget _buildCard() {
    final trip = widget.trip;
    final name = widget.vehicle?.name;
    return switch (_template) {
      StatCardTemplate.classic => _StatCard(trip: trip, vehicleName: name, fmtDuration: _fmtDuration),
      StatCardTemplate.route => _RouteCard(trip: trip, vehicleName: name, points: widget.points!, fmtDuration: _fmtDuration),
      StatCardTemplate.lean => _LeanCard(trip: trip, vehicleName: name, maxLeanDeg: _maxLeanDeg!, fmtDuration: _fmtDuration),
      StatCardTemplate.story => _StoryCard(trip: trip, vehicleName: name, points: widget.points!, maxLeanDeg: _maxLeanDeg, fmtDuration: _fmtDuration),
    };
  }

  String _fmtDuration(int seconds) {
    final d = Duration(seconds: seconds);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      // The card is already laid out by the time this button is
      // tappable, but wait for a settled frame anyway — capturing mid-
      // build/layout is the classic way this kind of thing comes back
      // blank or partial.
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _cardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw StateError('Could not encode the card image.');

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/opentrip-trip-${widget.trip.id}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'My ${widget.trip.distanceKm.toStringAsFixed(1)} km trip, tracked with OpenTrip.',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn\'t share: $e')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share trip', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_available.length > 1) ...[
                NoctSegmentedControl<StatCardTemplate>(
                  options: [
                    for (final t in _available)
                      (t, switch (t) {
                        StatCardTemplate.classic => 'Classic',
                        StatCardTemplate.route => 'Route',
                        StatCardTemplate.lean => 'Lean',
                        StatCardTemplate.story => 'Story',
                      }),
                  ],
                  value: _template,
                  onChanged: (t) => setState(() => _template = t),
                ),
                const SizedBox(height: 16),
              ],
              Flexible(
                child: AspectRatio(
                  aspectRatio: _template == StatCardTemplate.story ? 9 / 16 : 4 / 5,
                  child: RepaintBoundary(key: _cardKey, child: _buildCard()),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _sharing ? null : _share,
                      child: _sharing
                          ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Ph.export_, size: 15, color: Noct.a200),
                                SizedBox(width: 8),
                                Text('Share'),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 46,
                    height: 46,
                    child: OutlinedButton(
                      onPressed: _sharing ? null : _share,
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        side: const BorderSide(color: Noct.divider),
                      ),
                      child: const Icon(Ph.downloadSimple, size: 16, color: Noct.n300),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.trip, required this.vehicleName, required this.fmtDuration});

  final Trip trip;
  final String? vehicleName;
  final String Function(int) fmtDuration;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Noct.rLg),
        boxShadow: Noct.shadowMd,
        // Fixed colors, not Theme.of(context) — this is a poster exported
        // as a PNG for sharing outside the app, so it should look the
        // same regardless of the viewing device's settings. The only
        // saturated fill anywhere in Nocturne — see app_theme.dart's
        // Noct.section.
        gradient: const LinearGradient(
          begin: Alignment(-0.5, -1),
          end: Alignment(0.5, 0.24),
          colors: [Noct.section, Noct.bg],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Ph.path, color: Noct.a300, size: 17),
              SizedBox(width: 8),
              Text('OPENTRIP', style: TextStyle(color: Noct.a300, fontWeight: FontWeight.w400, letterSpacing: 2.4, fontSize: 11)),
            ],
          ),
          const Spacer(),
          Text(trip.distanceKm.toStringAsFixed(1), style: Noct.stat(74)),
          const SizedBox(height: 6),
          const Text('kilometers', style: TextStyle(color: Noct.n400, fontSize: 14, fontWeight: FontWeight.w400)),
          const SizedBox(height: 24),
          Row(
            children: [
              _CardStat('Time', fmtDuration(trip.durationSeconds)),
              const SizedBox(width: 22),
              _CardStat('Avg km/h', trip.avgSpeedKph == null ? '—' : trip.avgSpeedKph!.toStringAsFixed(0)),
              const SizedBox(width: 22),
              _CardStat('Max km/h', trip.maxSpeedKph == null ? '—' : trip.maxSpeedKph!.toStringAsFixed(0)),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(vehicleName ?? 'Trip', style: const TextStyle(color: Noct.text, fontSize: 13, fontWeight: FontWeight.w400)),
              Text(fmtDayMonth(trip.startedAt), style: const TextStyle(color: Noct.n500, fontSize: 11.5)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardStat extends StatelessWidget {
  const _CardStat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(color: Noct.text, fontWeight: FontWeight.w500, fontSize: 15, fontFeatures: [FontFeature.tabularFigures()]),
        ),
        Text(label.toUpperCase(), style: const TextStyle(color: Noct.n500, fontSize: 10, letterSpacing: 1.0, fontWeight: FontWeight.w400)),
      ],
    );
  }
}


/// Shared poster chrome: the gradient backdrop every template sits on,
/// the OPENTRIP wordmark, and the vehicle/date footer.
class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.trip, required this.vehicleName, required this.child});

  final Trip trip;
  final String? vehicleName;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Noct.rLg),
        boxShadow: Noct.shadowMd,
        gradient: const LinearGradient(
          begin: Alignment(-0.5, -1),
          end: Alignment(0.5, 0.24),
          colors: [Noct.section, Noct.bg],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Ph.path, color: Noct.a300, size: 17),
              SizedBox(width: 8),
              Text('OPENTRIP', style: TextStyle(color: Noct.a300, fontWeight: FontWeight.w400, letterSpacing: 2.4, fontSize: 11)),
            ],
          ),
          Expanded(child: child),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  vehicleName ?? 'Trip',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Noct.text, fontSize: 13, fontWeight: FontWeight.w400),
                ),
              ),
              Text(fmtDayMonth(trip.startedAt), style: const TextStyle(color: Noct.n500, fontSize: 11.5)),
            ],
          ),
        ],
      ),
    );
  }
}

/// The ride's own shape, segment-colored by speed — the same scale as
/// ride analysis's speed map, so the card matches what's in the app.
class _SpeedRoutePainter extends CustomPainter {
  _SpeedRoutePainter(this.points);
  final List<TripPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    final fitted = fitRouteToBox([for (final p in points) (p.latitude, p.longitude)], size, 10);
    if (fitted.length < 2) return;
    final scaleMax = scaleMaxFor(points, RideMetric.speed);
    final glow = Paint()
      ..color = Noct.accent.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final glowPath = Path()..moveTo(fitted.first.dx, fitted.first.dy);
    for (final o in fitted.skip(1)) {
      glowPath.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(glowPath, glow);
    for (final s in segmentRoute(points, RideMetric.speed, scaleMax: scaleMax)) {
      final path = Path()..moveTo(fitted[s.startIndex].dx, fitted[s.startIndex].dy);
      for (var i = s.startIndex + 1; i <= s.endIndex; i++) {
        path.lineTo(fitted[i].dx, fitted[i].dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = s.level == null ? Noct.a300 : rampColor(s.level!)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.drawCircle(fitted.first, 4, Paint()..color = Noct.n200);
    canvas.drawCircle(fitted.last, 4, Paint()..color = Noct.a200);
  }

  @override
  bool shouldRepaint(_SpeedRoutePainter old) => old.points != points;
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.trip, required this.vehicleName, required this.points, required this.fmtDuration});

  final Trip trip;
  final String? vehicleName;
  final List<TripPoint> points;
  final String Function(int) fmtDuration;

  @override
  Widget build(BuildContext context) {
    return _CardFrame(
      trip: trip,
      vehicleName: vehicleName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: CustomPaint(size: Size.infinite, painter: _SpeedRoutePainter(points))),
          Row(
            children: [
              _CardStat('km', trip.distanceKm.toStringAsFixed(1)),
              const SizedBox(width: 22),
              _CardStat('Time', fmtDuration(trip.durationSeconds)),
              const SizedBox(width: 22),
              _CardStat('Max km/h', trip.maxSpeedKph == null ? '—' : trip.maxSpeedKph!.toStringAsFixed(0)),
            ],
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _LeanCard extends StatelessWidget {
  const _LeanCard({required this.trip, required this.vehicleName, required this.maxLeanDeg, required this.fmtDuration});

  final Trip trip;
  final String? vehicleName;
  final double maxLeanDeg;
  final String Function(int) fmtDuration;

  @override
  Widget build(BuildContext context) {
    return _CardFrame(
      trip: trip,
      vehicleName: vehicleName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final side = c.biggest.shortestSide;
                return Center(
                  child: SizedBox(
                    width: side,
                    height: side,
                    child: CustomPaint(
                      painter: _LeanGaugePainter(maxLeanDeg),
                      child: Align(
                        alignment: const Alignment(0, 0.45),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${maxLeanDeg.toStringAsFixed(0)}°', style: Noct.stat(side * 0.26)),
                            const Text('MAX LEAN', style: TextStyle(color: Noct.n400, fontSize: 11, letterSpacing: 1.6)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Row(
            children: [
              _CardStat('km', trip.distanceKm.toStringAsFixed(1)),
              const SizedBox(width: 22),
              _CardStat('Time', fmtDuration(trip.durationSeconds)),
              const SizedBox(width: 22),
              _CardStat('Max km/h', trip.maxSpeedKph == null ? '—' : trip.maxSpeedKph!.toStringAsFixed(0)),
            ],
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

/// A bike silhouette-free lean gauge: a half-dial from 60° left to 60°
/// right, with the max lean marked on both sides (the phone tracker is
/// unsigned, so the card doesn't claim a direction it can't know).
class _LeanGaugePainter extends CustomPainter {
  _LeanGaugePainter(this.leanDeg);
  final double leanDeg;

  static const _maxDial = 60.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.72);
    final radius = size.width * 0.44;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const top = -math.pi / 2;
    const span = (_maxDial / 90) * (math.pi / 2);
    final track = Paint()
      ..color = Noct.n800
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, top - span, span * 2, false, track);

    final sweep = (leanDeg.clamp(0, _maxDial) / 90) * (math.pi / 2);
    final level = (leanDeg / _maxDial).clamp(0.0, 1.0);
    final fill = Paint()
      ..color = rampColor(level)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, top - sweep, sweep, false, fill);
    canvas.drawArc(rect, top, sweep, false, fill);

    final tick = Paint()
      ..color = Noct.n600
      ..strokeWidth = 1.2;
    for (var d = -60; d <= 60; d += 15) {
      final a = top + (d / 90) * (math.pi / 2);
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(center + dir * (radius - 16), center + dir * (radius - 22), tick);
    }
  }

  @override
  bool shouldRepaint(_LeanGaugePainter old) => old.leanDeg != leanDeg;
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({
    required this.trip,
    required this.vehicleName,
    required this.points,
    required this.maxLeanDeg,
    required this.fmtDuration,
  });

  final Trip trip;
  final String? vehicleName;
  final List<TripPoint> points;
  final double? maxLeanDeg;
  final String Function(int) fmtDuration;

  @override
  Widget build(BuildContext context) {
    return _CardFrame(
      trip: trip,
      vehicleName: vehicleName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 18),
          Text(trip.distanceKm.toStringAsFixed(1), style: Noct.stat(68)),
          const Text('kilometers', style: TextStyle(color: Noct.n400, fontSize: 14)),
          Expanded(child: CustomPaint(size: Size.infinite, painter: _SpeedRoutePainter(points))),
          Wrap(
            spacing: 22,
            runSpacing: 14,
            children: [
              _CardStat('Time', fmtDuration(trip.durationSeconds)),
              _CardStat('Avg km/h', trip.avgSpeedKph == null ? '—' : trip.avgSpeedKph!.toStringAsFixed(0)),
              _CardStat('Max km/h', trip.maxSpeedKph == null ? '—' : trip.maxSpeedKph!.toStringAsFixed(0)),
              if (maxLeanDeg != null) _CardStat('Max lean', '${maxLeanDeg!.toStringAsFixed(0)}°'),
            ],
          ),
          const SizedBox(height: 22),
        ],
      ),
    );
  }
}
