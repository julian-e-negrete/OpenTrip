import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../auth/current_user.dart';
import '../data/models/trip.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/trip_repository.dart';
import '../gamification/gamification_service.dart';
import '../logging/log_buffer.dart';
import '../theme/app_theme.dart';
import '../theme/primitives.dart';
import '../trip/location_recorder.dart';

enum _Step { countdown, running, result }

/// One continuous roll race — a real drag-strip-style countdown (light
/// sequence, 3-2-1-GO), then a single uninterrupted run: 0-60 km/h is a
/// checkpoint that appears mid-run without stopping anything, 0-180 km/h
/// (or a 30-second cap, whichever comes first) is what actually ends it.
/// Deliberately not two separate timed tests — the timer starts once, at
/// GO, and never resets until the run finishes.
///
/// Under the hood this is a normal trip/location_recorder.dart recording
/// (so it's a real, replayable trip in the rider's history, same as one
/// started from the Record tab) — trip/accel_run_tracker.dart's
/// RollRaceTracker is what actually measures both checkpoints from the
/// same launch.
class SoloRaceScreen extends StatefulWidget {
  const SoloRaceScreen({super.key, required this.vehicle});

  final Vehicle vehicle;

  @override
  State<SoloRaceScreen> createState() => _SoloRaceScreenState();
}

/// Run ends 30s after GO if 180 km/h is never reached — a checkpoint
/// already captured (0-60) still stands; only the unreached one shows as
/// not hit.
const _maxRunSeconds = 30;

class _SoloRaceScreenState extends State<SoloRaceScreen> {
  final _recorder = LocationRecorder();
  final _audioPlayer = AudioPlayer();
  bool _audioContextConfigured = false;
  _Step _step = _Step.countdown;
  int _countdown = 3;
  bool _showGo = false;
  Timer? _countdownTimer;
  Timer? _goFlashTimer;
  Timer? _maxRunTimer;
  StreamSubscription<RecordingStats>? _statsSub;
  Trip? _trip;
  RecordingStats? _stats;
  double? _resultZeroToSixty;
  double? _resultZeroToOneEighty;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    logBuffer.add('Racing: countdown started — ${widget.vehicle.name}');
    _startCountdown();
  }

  void _startCountdown() {
    // A rider is watching the road, not the screen — the countdown needs
    // to be audible, not just visible (this is the whole reason it has a
    // sound at all: you react to a beep in your ear faster than to a
    // light you have to be looking at). Beeps for 3/2/1, a distinct
    // rising chirp for GO so the two are never confused by ear alone.
    unawaited(_playBeep());
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown <= 1) {
        timer.cancel();
        unawaited(_beginRun());
        return;
      }
      setState(() => _countdown--);
      unawaited(_playBeep());
    });
  }

  Future<void> _configureAudioContextIfNeeded() async {
    if (_audioContextConfigured) return;
    // Same posture as trip/camera_alerts.dart's alert beep: the default
    // audio focus grabs exclusive control and pauses whatever else is
    // playing (a rider's own music) — duckOthers just lowers it instead,
    // so the countdown plays on top rather than cutting the music off.
    await _audioPlayer.setAudioContext(AudioContextConfig(focus: AudioContextConfigFocus.duckOthers).build());
    _audioContextConfigured = true;
  }

  Future<void> _playBeep() async {
    try {
      await _configureAudioContextIfNeeded();
      await _audioPlayer.play(AssetSource('sounds/race_countdown_beep.wav'));
    } catch (e) {
      logBuffer.add('Racing: countdown beep failed — $e');
    }
  }

  Future<void> _playGo() async {
    try {
      await _configureAudioContextIfNeeded();
      await _audioPlayer.play(AssetSource('sounds/race_countdown_go.wav'));
    } catch (e) {
      logBuffer.add('Racing: GO sound failed — $e');
    }
  }

  Future<void> _beginRun() async {
    unawaited(_playGo());
    setState(() => _showGo = true);
    _goFlashTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showGo = false);
    });

    final userId = await CurrentUser.instance.id();
    final trip = await TripRepository.instance.startTrip(userId: userId, vehicleId: widget.vehicle.id);
    logBuffer.add('Racing: GO — trip ${trip.id}, ends at 180 km/h or ${_maxRunSeconds}s');
    // The timer starts here, at GO, and runs continuously until the race
    // actually finishes — nothing below resets or restarts it.
    await _recorder.start(trip.id);
    if (!mounted) return;
    setState(() {
      _trip = trip;
      _step = _Step.running;
    });
    _statsSub = _recorder.statsStream.listen(_onStats);
    _maxRunTimer = Timer(const Duration(seconds: _maxRunSeconds), () => unawaited(_finish()));
  }

  void _onStats(RecordingStats stats) {
    if (!mounted) return;
    setState(() => _stats = stats);
    // 0-60 is just a checkpoint — capturing it doesn't touch _step, the
    // timer, or the recording. Only reaching 180 ends the race early.
    if (_recorder.best0To180Seconds != null) unawaited(_finish());
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    _maxRunTimer?.cancel();
    await _statsSub?.cancel();
    final finalStats = await _recorder.stop();
    final trip = _trip;
    if (trip == null) {
      logBuffer.add('Racing: _finish called with no active trip — nothing to save');
      return;
    }

    final zeroToSixty = _recorder.best0To60Seconds;
    final zeroToOneEighty = _recorder.best0To180Seconds;
    logBuffer.add(
      'Racing: finished — trip ${trip.id}, 0-60=${zeroToSixty?.toStringAsFixed(2) ?? "not reached"}s, '
      '0-180=${zeroToOneEighty?.toStringAsFixed(2) ?? "not reached"}s',
    );

    final finished = trip.finish(
      endedAt: DateTime.now(),
      distanceMeters: finalStats.distanceMeters,
      durationSeconds: finalStats.elapsed.inSeconds,
      avgSpeedKph: finalStats.avgSpeedKph,
      maxSpeedKph: finalStats.maxSpeedKph,
      pointCount: finalStats.pointCount,
      best0To60Seconds: zeroToSixty,
      best0To180Seconds: zeroToOneEighty,
    );
    await TripRepository.instance.finishTrip(finished);

    final userId = await CurrentUser.instance.id();
    final points = await TripRepository.instance.pointsForTrip(finished.id);
    unawaited(GamificationService.processFinishedTrip(userId: userId, trip: finished, points: points));

    if (!mounted) return;
    setState(() {
      _resultZeroToSixty = zeroToSixty;
      _resultZeroToOneEighty = zeroToOneEighty;
      _step = _Step.result;
    });
  }

  Future<void> _cancel() async {
    logBuffer.add('Racing: cancelled during ${_step.name}${_trip == null ? '' : ' — discarding trip ${_trip!.id}'}');
    _countdownTimer?.cancel();
    _goFlashTimer?.cancel();
    _maxRunTimer?.cancel();
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
    _goFlashTimer?.cancel();
    _maxRunTimer?.cancel();
    _statsSub?.cancel();
    unawaited(_recorder.dispose());
    unawaited(_audioPlayer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Noct.bg,
      appBar: AppBar(
        backgroundColor: Noct.bg,
        title: const Text('Roll race'),
        leading: _step == _Step.result
            ? null
            : IconButton(icon: const Icon(Icons.close), onPressed: _cancel),
      ),
      body: SafeArea(
        child: switch (_step) {
          _Step.countdown => _CountdownView(count: _countdown, showGo: _showGo),
          _Step.running => _RunningView(
              stats: _stats,
              zeroToSixty: _recorder.best0To60Seconds,
              justStarted: _showGo,
            ),
          _Step.result => _ResultView(
              zeroToSixty: _resultZeroToSixty,
              zeroToOneEighty: _resultZeroToOneEighty,
              onDone: () => Navigator.of(context).pop(),
            ),
        },
      ),
    );
  }
}

/// A real drag-strip "Christmas tree" feel: three lights climb amber as
/// the count falls, then flash green together at GO — a countdown a
/// rider can read at a glance without parsing a number under load.
class _StartingLight extends StatelessWidget {
  const _StartingLight({required this.count, required this.go});
  final int count;
  final bool go;

  @override
  Widget build(BuildContext context) {
    // count 3 -> 1 light, 2 -> 2 lights, 1 -> 3 lights, all amber; GO -> 3 green.
    final litCount = go ? 3 : (4 - count).clamp(0, 3);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < litCount ? (go ? Colors.green : Colors.amber) : Noct.n800,
                boxShadow: i < litCount
                    ? [BoxShadow(color: (go ? Colors.green : Colors.amber).withValues(alpha: 0.6), blurRadius: 12)]
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

class _CountdownView extends StatelessWidget {
  const _CountdownView({required this.count, required this.showGo});
  final int count;
  final bool showGo;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StartingLight(count: count, go: showGo),
          const SizedBox(height: 28),
          Text(showGo ? 'GO' : '$count', style: Noct.stat(96, color: showGo ? Colors.green : null)),
          const SizedBox(height: 12),
          if (!showGo) const Text('Get ready...', style: TextStyle(fontSize: 14, color: Noct.n500)),
        ],
      ),
    );
  }
}

class _RunningView extends StatelessWidget {
  const _RunningView({required this.stats, required this.zeroToSixty, required this.justStarted});
  final RecordingStats? stats;
  final double? zeroToSixty;
  final bool justStarted;

  @override
  Widget build(BuildContext context) {
    final speed = stats?.currentSpeedKph;
    final elapsed = stats?.elapsed;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedOpacity(
            opacity: justStarted ? 1 : 0,
            duration: const Duration(milliseconds: 400),
            child: const Text('GO', style: TextStyle(fontSize: 20, color: Colors.green, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 8),
          Text(speed == null ? '—' : speed.toStringAsFixed(0), style: Noct.stat(72)),
          const SizedBox(height: 4),
          const Text('KM/H', style: Noct.statLabel),
          const SizedBox(height: 18),
          Text(
            elapsed == null ? '0.0s' : '${(elapsed.inMilliseconds / 1000.0).toStringAsFixed(1)}s',
            style: const TextStyle(fontSize: 15, color: Noct.n400, fontFeatures: [FontFeature.tabularFigures()]),
          ),
          const SizedBox(height: 28),
          _CheckpointBadge(label: '0-60 km/h', seconds: zeroToSixty),
          const SizedBox(height: 10),
          const Text('Reach 180 km/h to finish', style: TextStyle(fontSize: 13, color: Noct.n500)),
        ],
      ),
    );
  }
}

class _CheckpointBadge extends StatelessWidget {
  const _CheckpointBadge({required this.label, required this.seconds});
  final String label;
  final double? seconds;

  @override
  Widget build(BuildContext context) {
    final hit = seconds != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: hit ? Noct.a900 : Noct.surface,
        borderRadius: BorderRadius.circular(Noct.rMd),
        border: Border.all(color: hit ? Noct.a700 : Noct.n800),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: hit ? Noct.a100 : Noct.n500)),
          const SizedBox(width: 8),
          Text(
            hit ? '${seconds!.toStringAsFixed(2)}s ✓' : '—',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: hit ? Noct.a100 : Noct.n500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.zeroToSixty, required this.zeroToOneEighty, required this.onDone});
  final double? zeroToSixty;
  final double? zeroToOneEighty;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ResultRow(label: '0-60 km/h', seconds: zeroToSixty),
            const SizedBox(height: 18),
            _ResultRow(label: '0-180 km/h', seconds: zeroToOneEighty, emphasize: true),
            const SizedBox(height: 32),
            NoctOutlinedButton(label: 'Done', onPressed: onDone),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.seconds, this.emphasize = false});
  final String label;
  final double? seconds;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label.toUpperCase(), style: Noct.statLabel),
        const SizedBox(height: 6),
        Text(
          seconds == null ? 'DNF' : '${seconds!.toStringAsFixed(2)}s',
          style: Noct.stat(emphasize ? 56 : 36, color: seconds == null ? Noct.n500 : null),
        ),
      ],
    );
  }
}
