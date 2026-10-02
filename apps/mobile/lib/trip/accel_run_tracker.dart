/// Times a single continuous roll race from a standing start: 0-60 km/h
/// as an in-run checkpoint, then 0-180 km/h as the finish condition, both
/// measured from the *same* launch — not two independent brackets. Fed
/// one GPS fix at a time via [onFix].
///
/// "Launch" is the last fix at or below [_restThresholdKph] before speed
/// climbs away from it — continuously updated while stationary, so a
/// rider who idles at a light for a while still gets a correct 0-60 time
/// from the moment they actually pull away, not from whenever they first
/// rolled to a stop. Once moving, a run has [_maxWindowSeconds] to reach
/// 180 km/h; reaching it finishes the run immediately, and running out
/// of time ends it at the cap — either way, whatever 0-60 time was
/// already captured during that window still stands, since it's just a
/// checkpoint within the run, not a separate pass/fail test of its own.
///
/// Keeps the *best* of however many qualifying launches happen — a
/// dedicated racing/ attempt only ever has one, but this also runs
/// during ordinary rides (trip/location_recorder.dart), where a rider
/// might pull away hard more than once.
class RollRaceTracker {
  static const _restThresholdKph = 2.0;
  static const _checkpointKph = 60.0;
  static const _finishKph = 180.0;
  static const _maxWindowSeconds = 30.0;

  DateTime? _launchAt;
  double? _thisRunZeroToSixty;
  bool _thisRunDone = false;

  double? bestZeroToSixtySeconds;
  double? bestZeroToOneEightySeconds;

  void onFix(double speedKph, DateTime timestamp) {
    if (speedKph <= _restThresholdKph) {
      _launchAt = timestamp;
      _thisRunZeroToSixty = null;
      _thisRunDone = false;
      return;
    }

    final launchAt = _launchAt;
    if (launchAt == null || _thisRunDone) return;

    final elapsed = timestamp.difference(launchAt).inMilliseconds / 1000.0;
    if (elapsed > _maxWindowSeconds) {
      _thisRunDone = true;
      return;
    }

    if (_thisRunZeroToSixty == null && speedKph >= _checkpointKph) {
      _thisRunZeroToSixty = elapsed;
      if (bestZeroToSixtySeconds == null || elapsed < bestZeroToSixtySeconds!) {
        bestZeroToSixtySeconds = elapsed;
      }
    }

    if (speedKph >= _finishKph) {
      if (bestZeroToOneEightySeconds == null || elapsed < bestZeroToOneEightySeconds!) {
        bestZeroToOneEightySeconds = elapsed;
      }
      _thisRunDone = true;
    }
  }

  void reset() {
    _launchAt = null;
    _thisRunZeroToSixty = null;
    _thisRunDone = false;
    bestZeroToSixtySeconds = null;
    bestZeroToOneEightySeconds = null;
  }
}
