import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models/trip.dart';
import '../data/models/vehicle.dart';
import '../theme/app_theme.dart';
import '../theme/date_fmt.dart';
import '../theme/ph_icons.dart';

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
      appBar: AppBar(
        title: const Text('Share trip', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 4 / 5,
                child: RepaintBoundary(
                  key: _cardKey,
                  child: _StatCard(trip: trip, vehicleName: widget.vehicle?.name, fmtDuration: _fmtDuration),
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
