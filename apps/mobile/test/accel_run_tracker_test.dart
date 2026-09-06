import 'package:flutter_test/flutter_test.dart';
import 'package:opentrip_mobile/trip/accel_run_tracker.dart';

void main() {
  group('AccelRunTracker', () {
    final start = DateTime(2026, 1, 1, 12, 0, 0);

    test('times a clean 0-60 run', () {
      final tracker = AccelRunTracker(lowThresholdKph: 2, highThresholdKph: 60);
      tracker.onFix(0, start);
      tracker.onFix(30, start.add(const Duration(milliseconds: 2000)));
      tracker.onFix(61, start.add(const Duration(milliseconds: 4200)));
      expect(tracker.bestSeconds, closeTo(4.2, 0.001));
    });

    test('keeps the best of several qualifying runs', () {
      final tracker = AccelRunTracker(lowThresholdKph: 2, highThresholdKph: 60);
      // First run: 5s.
      tracker.onFix(0, start);
      tracker.onFix(61, start.add(const Duration(seconds: 5)));
      // Drop back down, then a faster second run: 3s.
      tracker.onFix(1, start.add(const Duration(seconds: 10)));
      tracker.onFix(65, start.add(const Duration(seconds: 13)));
      expect(tracker.bestSeconds, closeTo(3.0, 0.001));
    });

    test('a rolling start (already past the low threshold) still times correctly', () {
      final tracker = AccelRunTracker(lowThresholdKph: 100, highThresholdKph: 180);
      tracker.onFix(100, start);
      tracker.onFix(140, start.add(const Duration(seconds: 3)));
      tracker.onFix(181, start.add(const Duration(seconds: 6)));
      expect(tracker.bestSeconds, closeTo(6.0, 0.001));
    });

    test('cruising above the high threshold without re-arming does not re-trigger', () {
      final tracker = AccelRunTracker(lowThresholdKph: 2, highThresholdKph: 60);
      tracker.onFix(0, start);
      tracker.onFix(61, start.add(const Duration(seconds: 4)));
      expect(tracker.bestSeconds, closeTo(4.0, 0.001));
      // Still above threshold on every subsequent fix — no new "run" should
      // start or finish just from continuing to cruise fast.
      tracker.onFix(65, start.add(const Duration(seconds: 20)));
      tracker.onFix(70, start.add(const Duration(seconds: 40)));
      expect(tracker.bestSeconds, closeTo(4.0, 0.001));
    });

    test('never crossing the high threshold leaves bestSeconds null', () {
      final tracker = AccelRunTracker(lowThresholdKph: 2, highThresholdKph: 60);
      tracker.onFix(0, start);
      tracker.onFix(45, start.add(const Duration(seconds: 5)));
      tracker.onFix(50, start.add(const Duration(seconds: 8)));
      expect(tracker.bestSeconds, isNull);
    });

    test('reset clears both the armed state and the best time', () {
      final tracker = AccelRunTracker(lowThresholdKph: 2, highThresholdKph: 60);
      tracker.onFix(0, start);
      tracker.onFix(61, start.add(const Duration(seconds: 4)));
      expect(tracker.bestSeconds, isNotNull);
      tracker.reset();
      expect(tracker.bestSeconds, isNull);
      // Re-arm needed again — a fix straight past threshold with no prior
      // low-speed fix since reset shouldn't count.
      tracker.onFix(65, start.add(const Duration(seconds: 100)));
      expect(tracker.bestSeconds, isNull);
    });
  });
}
