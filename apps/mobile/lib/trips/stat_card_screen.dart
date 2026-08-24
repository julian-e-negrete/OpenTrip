import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models/trip.dart';
import '../data/models/vehicle.dart';

/// Renders a trip's key numbers as a shareable image — tap Share to
/// capture the card below (via [RepaintBoundary]) and hand it to the
/// OS share sheet. Purely client-side: no backend involved, nothing
/// generated or stored server-side, just a PNG written to a temp file
/// for the share sheet to read.
class StatCardScreen extends StatefulWidget {
  const StatCardScreen({super.key, required this.trip, required this.vehicle});

  final Trip trip;
  final Vehicle? vehicle;

  @override
  State<StatCardScreen> createState() => _StatCardScreenState();
}

class _StatCardScreenState extends State<StatCardScreen> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

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
    final trip = widget.trip;
    return Scaffold(
      appBar: AppBar(title: const Text('Share trip')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RepaintBoundary(
                key: _cardKey,
                child: _StatCard(trip: trip, vehicleName: widget.vehicle?.name, fmtDuration: _fmtDuration),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _sharing ? null : _share,
                icon: _sharing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.ios_share),
                label: Text(_sharing ? 'Preparing…' : 'Share'),
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
    final dateLabel = trip.startedAt.toLocal().toString().substring(0, 10);
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          // Fixed brand colors, not Theme.of(context) — this is a poster
          // exported as a PNG for sharing outside the app (see
          // StatCardScreen's doc comment), so it should look the same
          // regardless of the viewing device's light/dark setting, the
          // same way a logo doesn't reflow with a website's theme toggle.
          // Matches app_theme.dart's dark palette + coral accent directly
          // rather than tracking it live.
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF251731), Color(0xFF160D1F)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.route_outlined, color: Color(0xFFFF4D6D), size: 20),
                SizedBox(width: 8),
                Text(
                  'OPENTRIP',
                  style: TextStyle(
                    color: Color(0xFFFF4D6D),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              trip.distanceKm.toStringAsFixed(1),
              style: const TextStyle(color: Colors.white, fontSize: 72, fontWeight: FontWeight.w800, height: 1),
            ),
            const Text('kilometers', style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _CardStat('Time', fmtDuration(trip.durationSeconds)),
                _CardStat(
                  'Avg speed',
                  trip.avgSpeedKph == null ? '—' : '${trip.avgSpeedKph!.toStringAsFixed(0)} km/h',
                ),
                _CardStat(
                  'Max speed',
                  trip.maxSpeedKph == null ? '—' : '${trip.maxSpeedKph!.toStringAsFixed(0)} km/h',
                ),
              ],
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  vehicleName ?? 'Trip',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                Text(dateLabel, style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ],
            ),
          ],
        ),
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
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }
}
