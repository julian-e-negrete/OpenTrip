/// Small hand-rolled date labels — the app has no `intl` dependency, and
/// these are the only formats the Nocturne screens need (list rows'
/// dates, kickers, month switchers).
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String monthAbbrev(int month) => _months[month - 1];

String weekdayAbbrev(DateTime d) => _weekdays[d.weekday - 1];

/// e.g. "24 Aug".
String fmtDayMonth(DateTime d) => '${d.day} ${monthAbbrev(d.month)}';

/// e.g. "Sat 24 Aug".
String fmtWeekdayDayMonth(DateTime d) => '${weekdayAbbrev(d)} ${fmtDayMonth(d)}';

/// e.g. "August".
String fmtMonthName(DateTime d) => switch (d.month) {
  1 => 'January',
  2 => 'February',
  3 => 'March',
  4 => 'April',
  5 => 'May',
  6 => 'June',
  7 => 'July',
  8 => 'August',
  9 => 'September',
  10 => 'October',
  11 => 'November',
  _ => 'December',
};
