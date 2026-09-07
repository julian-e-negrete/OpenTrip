import 'package:flutter_test/flutter_test.dart';
import 'package:opentrip_mobile/trip/accel_run_tracker.dart';

void main() {
  group('RollRaceTracker', () {
    final start = DateTime(2026, 1, 1, 12, 0, 0);

    test('times both checkpoints from the same launch, run finishes at 180', () {
      final tracker = RollRaceTracker();
      tracker.onFix(0, start);
      tracker.onFix(30, start.add(const Duration(milliseconds: 2000)));
      tracker.onFix(61, start.add(const Duration(milliseconds: 4200)));
      expect(tracker.bestZeroToSixtySeconds, closeTo(4.2, 0.001));
      expect(tracker.bestZeroToOneEightySeconds, isNull);

      // The timer keeps running — the 0-60 capture doesn't reset or
      // interrupt anything.
      tracker.onFix(120, start.add(const Duration(seconds: 8)));
      tracker.onFix(181, start.add(const Duration(seconds: 11)));
      expect(tracker.bestZeroToSixtySeconds, closeTo(4.2, 0.001));
      expect(tracker.bestZeroToOneEightySeconds, closeTo(11.0, 0.001));
    });

    test('ends at the 30s cap if 180 is never reached, keeping the 0-60 already captured', () {
      final tracker = RollRaceTracker();
      tracker.onFix(0, start);
      tracker.onFix(61, start.add(const Duration(seconds: 5)));
      tracker.onFix(150, start.add(const Duration(seconds: 20)));
      // Past the 30s window — no further crossings should count.
      tracker.onFix(181, start.add(const Duration(seconds: 31)));
      expect(tracker.bestZeroToSixtySeconds, closeTo(5.0, 0.001));
      expect(tracker.bestZeroToOneEightySeconds, isNull);
    });

    test('a real stoplight idle before launch does not eat into the 30s window', () {
      final tracker = RollRaceTracker();
      // Idling at rest for a while — armedAt keeps sliding forward.
      tracker.onFix(0, start);
      tracker.onFix(1, start.add(const Duration(seconds: 30)));
      tracker.onFix(0, start.add(const Duration(seconds: 60)));
      // Launch happens here — the clock starts now, not back at `start`.
      tracker.onFix(65, start.add(const Duration(seconds: 64)));
      expect(tracker.bestZeroToSixtySeconds, closeTo(4.0, 0.001));
    });

    test('never reaching 60 leaves both checkpoints null', () {
      final tracker = RollRaceTracker();
      tracker.onFix(0, start);
      tracker.onFix(40, start.add(const Duration(seconds: 5)));
      tracker.onFix(50, start.add(const Duration(seconds: 10)));
      expect(tracker.bestZeroToSixtySeconds, isNull);
      expect(tracker.bestZeroToOneEightySeconds, isNull);
    });

    test('keeps the best across more than one qualifying launch', () {
      final tracker = RollRaceTracker();
      // First launch: 0-60 in 5s.
      tracker.onFix(0, start);
      tracker.onFix(61, start.add(const Duration(seconds: 5)));
      // Back to a stop, then a faster second launch: 0-60 in 3s.
      tracker.onFix(0, start.add(const Duration(seconds: 40)));
      tracker.onFix(65, start.add(const Duration(seconds: 43)));
      expect(tracker.bestZeroToSixtySeconds, closeTo(3.0, 0.001));
    });

    test('reset clears everything, including in-progress launch state', () {
      final tracker = RollRaceTracker();
      tracker.onFix(0, start);
      tracker.onFix(61, start.add(const Duration(seconds: 4)));
      expect(tracker.bestZeroToSixtySeconds, isNotNull);
      tracker.reset();
      expect(tracker.bestZeroToSixtySeconds, isNull);
      expect(tracker.bestZeroToOneEightySeconds, isNull);
      // No launch armed post-reset — a fix straight past threshold with
      // no prior rest fix shouldn't count.
      tracker.onFix(65, start.add(const Duration(seconds: 100)));
      expect(tracker.bestZeroToSixtySeconds, isNull);
    });
  });
}
