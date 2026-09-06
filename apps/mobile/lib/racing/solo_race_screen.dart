import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/current_user.dart';
import '../data/models/trip.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/trip_repository.dart';
import '../gamification/gamification_service.dart';
import '../theme/app_theme.dart';
import '../theme/primitives.dart';
import '../trip/location_recorder.dart';
import 'accel_bracket.dart';

enum _Step { countdown, running, result }

/// A deliberate, timed acceleration attempt — countdown, then a normal
/// trip/location_recorder.dart recording (so it's a real, replayable trip
/// in the rider's history, same as one started from the Record tab) that
/// auto-finishes the moment the selected bracket's timer
/// (trip/accel_run_tracker.dart, surfaced via LocationRecorder) reports a
/// result, or after [AccelBracket.dnfSeconds] with no result (DNF).
///
/// Deliberately skips the ordinary Record flow's camera alerts display,
/// lean-angle opt-in, and Spotify logging — none of those matter for a
/// short, straight acceleration run, and keeping this screen narrowly
/// scoped to "how fast did I get from A to B" keeps its own state machine
/// simple. Territory/trophy processing still runs, same as any trip.
class SoloRaceScreen extends StatefulWidget {
  const SoloRaceScreen({super.key, required this.vehicle, required this.bracket});

  final Vehicle vehicle;
  final AccelBracket bracket;

  @override
  State<SoloRaceScreen> createState() => _SoloRaceScreenState();
}

class _SoloRaceScreenState extends State<SoloRaceScreen> {
  final _recorder = LocationRecorder();
  _Step _step = _Step.countdown;
  int _countdown = 3;
  Timer? _countdownTimer;
  Timer? _dnfTimer;
  StreamSubscription<RecordingStats>? _statsSub;
  Trip? _trip;
  RecordingStats? _stats;
  double? _resultSeconds;
  bool _dnf = false;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown <= 1) {
        timer.cancel();
        unawaited(_beginRun());
        return;
      }
      setState(() => _countdown--);
    });
  }

  Future<void> _beginRun() async {
    final userId = await CurrentUser.instance.id();
    final trip = await TripRepository.instance.startTrip(userId: userId, vehicleId: widget.vehicle.id);
    await _recorder.start(trip.id);
    if (!mounted) return;
    setState(() {
      _trip = trip;
      _step = _Step.running;
    });
    _statsSub = _recorder.statsStream.listen(_onStats);
    _dnfTimer = Timer(Duration(seconds: widget.bracket.dnfSeconds), () => unawaited(_finish(dnf: true)));
  }

  void _onStats(RecordingStats stats) {
    if (!mounted) return;
    setState(() => _stats = stats);
    final achieved = widget.bracket == AccelBracket.zeroToSixty
        ? _recorder.best0To60Seconds
        : _recorder.best100To180Seconds;
    if (achieved != null) unawaited(_finish(dnf: false, seconds: achieved));
  }

  Future<void> _finish({required bool dnf, double? seconds}) async {
    if (_finishing) return;
    _finishing = true;
    _dnfTimer?.cancel();
    await _statsSub?.cancel();
    final finalStats = await _recorder.stop();
    final trip = _trip;
    if (trip == null) return;

    final finished = trip.finish(
      endedAt: DateTime.now(),
      distanceMeters: finalStats.distanceMeters,
      durationSeconds: finalStats.elapsed.inSeconds,
      avgSpeedKph: finalStats.avgSpeedKph,
      maxSpeedKph: finalStats.maxSpeedKph,
      pointCount: finalStats.pointCount,
      best0To60Seconds: _recorder.best0To60Seconds,
      best100To180Seconds: _recorder.best100To180Seconds,
    );
    await TripRepository.instance.finishTrip(finished);

    final userId = await CurrentUser.instance.id();
    final points = await TripRepository.instance.pointsForTrip(finished.id);
    unawaited(GamificationService.processFinishedTrip(userId: userId, trip: finished, points: points));

    if (!mounted) return;
    setState(() {
      _dnf = dnf;
      _resultSeconds = seconds;
      _step = _Step.result;
    });
  }

  Future<void> _cancel() async {
    _countdownTimer?.cancel();
    _dnfTimer?.cancel();
    await _statsSub?.cancel();
    final trip = _trip;
    if (trip != null) {
      await _recorder.stop();
      // An abandoned attempt shouldn't linger as a zero-stat trip in the
      // rider's history — same posture as any recording that never
      // finishes cleanly, just handled explicitly here since cancelling
      // is a normal, expected action on this screen (unlike a crash).
      await TripRepository.instance.deleteTrip(trip.id);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _dnfTimer?.cancel();
    _statsSub?.cancel();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Noct.bg,
      appBar: AppBar(
        backgroundColor: Noct.bg,
        title: Text(widget.bracket.label),
        leading: _step == _Step.result
            ? null
            : IconButton(icon: const Icon(Icons.close), onPressed: _cancel),
      ),
      body: SafeArea(
        child: switch (_step) {
          _Step.countdown => _CountdownView(count: _countdown),
          _Step.running => _RunningView(stats: _stats, bracket: widget.bracket),
          _Step.result => _ResultView(
              dnf: _dnf,
              seconds: _resultSeconds,
              bracket: widget.bracket,
              onDone: () => Navigator.of(context).pop(),
            ),
        },
      ),
    );
  }
}

class _CountdownView extends StatelessWidget {
  const _CountdownView({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count', style: Noct.stat(96)),
          const SizedBox(height: 12),
          const Text('Get ready...', style: TextStyle(fontSize: 14, color: Noct.n500)),
        ],
      ),
    );
  }
}

class _RunningView extends StatelessWidget {
  const _RunningView({required this.stats, required this.bracket});
  final RecordingStats? stats;
  final AccelBracket bracket;

  @override
  Widget build(BuildContext context) {
    final speed = stats?.currentSpeedKph;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(speed == null ? '—' : speed.toStringAsFixed(0), style: Noct.stat(72)),
          const SizedBox(height: 4),
          const Text('KM/H', style: Noct.statLabel),
          const SizedBox(height: 28),
          Text('Reach ${bracket.label} to finish', style: const TextStyle(fontSize: 14, color: Noct.n500)),
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.dnf, required this.seconds, required this.bracket, required this.onDone});
  final bool dnf;
  final double? seconds;
  final AccelBracket bracket;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              dnf ? 'DNF' : '${seconds!.toStringAsFixed(2)}s',
              style: Noct.stat(64, color: dnf ? Noct.n500 : null),
            ),
            const SizedBox(height: 8),
            Text(
              dnf
                  ? 'Didn\'t reach ${bracket.label} within ${bracket.dnfSeconds}s'
                  : bracket.label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Noct.n500),
            ),
            const SizedBox(height: 32),
            NoctOutlinedButton(label: 'Done', onPressed: onDone),
          ],
        ),
      ),
    );
  }
}
