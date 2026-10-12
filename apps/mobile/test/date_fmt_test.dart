import 'package:flutter_test/flutter_test.dart';
import 'package:opentrip_mobile/theme/date_fmt.dart';

void main() {
  test('fmtDuration: seconds under a minute, minutes under an hour, then h+m', () {
    expect(fmtDuration(0), '0s');
    expect(fmtDuration(45), '45s');
    expect(fmtDuration(60), '1m');
    expect(fmtDuration(22 * 60 + 59), '22m');
    expect(fmtDuration(3600), '1h 0m');
    expect(fmtDuration(3600 + 5 * 60), '1h 5m');
    expect(fmtDuration(-3), '0s');
  });

  test('fmtTripDate: year only appears for another year', () {
    final now = DateTime(2026, 10, 12);
    expect(fmtTripDate(DateTime(2026, 8, 24), now: now), '24 Aug');
    expect(fmtTripDate(DateTime(2025, 8, 24), now: now), '24 Aug 2025');
    expect(fmtTripDate(DateTime(2026, 8, 24), withWeekday: true, now: now), 'Mon 24 Aug');
  });

  test('fmtTimeOfDay: zero-padded 24-hour clock', () {
    expect(fmtTimeOfDay(DateTime(2026, 1, 1, 7, 5)), '07:05');
    expect(fmtTimeOfDay(DateTime(2026, 1, 1, 23, 59)), '23:59');
  });
}
