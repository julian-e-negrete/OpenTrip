/// Times how long it takes speed to climb from [lowThresholdKph] to
/// [highThresholdKph] — e.g. a 0-60 km/h or 100-180 km/h run — fed one GPS
/// fix at a time via [onFix]. Keeps the *best* (lowest) time seen across
/// however many qualifying runs happen during a recording, same "best so
/// far" shape as trip/location_recorder.dart's other behavior stats.
///
/// Deliberately not a fixed-size sample window: "armed" just means "at or
/// below the low threshold as of the last fix that was", so a run starts
/// counting from whichever fix most recently touched the low end, and a
/// rolling start (e.g. already at 100 km/h, no dead stop needed) times
/// correctly too. Requires dropping back to/below the low threshold again
/// before another run can count — otherwise cruising above the high
/// threshold would spuriously "finish" a new run on every single fix.
class AccelRunTracker {
  AccelRunTracker({required this.lowThresholdKph, required this.highThresholdKph});

  final double lowThresholdKph;
  final double highThresholdKph;

  DateTime? _armedAt;
  double? bestSeconds;

  void onFix(double speedKph, DateTime timestamp) {
    if (speedKph <= lowThresholdKph) {
      _armedAt = timestamp;
      return;
    }
    final armedAt = _armedAt;
    if (armedAt != null && speedKph >= highThresholdKph) {
      final seconds = timestamp.difference(armedAt).inMilliseconds / 1000.0;
      if (bestSeconds == null || seconds < bestSeconds!) bestSeconds = seconds;
      _armedAt = null;
    }
  }

  void reset() {
    _armedAt = null;
    bestSeconds = null;
  }
}
