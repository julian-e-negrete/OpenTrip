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
}
