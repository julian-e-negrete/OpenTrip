import 'package:flutter/material.dart';

import '../data/repositories/trip_repository.dart';
import '../theme/app_theme.dart';
import '../trip/route_simplify.dart';

/// A trip's route, simplified and fit into a small box — the route
/// thumbnail on Trips' route-card variant and the route glyph on the
/// dense-log variant / Vehicle detail's recent-trips rows.
class RouteThumbnail extends StatefulWidget {
  const RouteThumbnail({
    super.key,
    required this.tripId,
    this.strokeWidth = 2.5,
    this.color = Noct.accent,
    this.opacity = 1.0,
    this.inset = 8,
  });

  final String tripId;
  final double strokeWidth;
  final Color color;
  final double opacity;
  final double inset;

  @override
  State<RouteThumbnail> createState() => _RouteThumbnailState();
}

class _RouteThumbnailState extends State<RouteThumbnail> {
  late final Future<List<LatLon>> _future = TripRepository.instance
      .pointsForTrip(widget.tripId)
      .then((points) => simplifyRoute([for (final p in points) (p.latitude, p.longitude)]));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LatLon>>(
      future: _future,
      builder: (context, snapshot) {
        final points = snapshot.data;
        if (points == null || points.length < 2) return const SizedBox.shrink();
        return CustomPaint(
          size: Size.infinite,
          painter: _RoutePainter(
            points: points,
            strokeWidth: widget.strokeWidth,
            color: widget.color.withValues(alpha: widget.color.a * widget.opacity),
            inset: widget.inset,
          ),
        );
      },
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({required this.points, required this.strokeWidth, required this.color, required this.inset});

  final List<LatLon> points;
  final double strokeWidth;
  final Color color;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final fitted = fitRouteToBox(points, size, inset);
    if (fitted.length < 2) return;
    final path = Path()..moveTo(fitted.first.dx, fitted.first.dy);
    for (final p in fitted.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
