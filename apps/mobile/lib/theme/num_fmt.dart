/// Thin-space-grouped integers — Ranks' numbers read `4 812`, not
/// `4,812` (design handoff §5). No `intl` dependency in this app, so
/// this is hand-rolled rather than pulling one in for a single format.
String fmtThousands(int n) {
  final digits = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
    buf.write(digits[i]);
  }
  return n < 0 ? '-$buf' : buf.toString();
}
