/// Which of trip/location_recorder.dart's two acceleration timers a solo
/// race run is watching — the thresholds themselves live there
/// (trip/accel_run_tracker.dart), this just names the two options for the
/// UI and picks the right result off a finished [Trip].
enum AccelBracket {
  zeroToSixty('0-60 km/h', dnfSeconds: 30),
  hundredToOneEighty('100-180 km/h', dnfSeconds: 30);

  const AccelBracket(this.label, {required this.dnfSeconds});

  final String label;

  /// How long from GO before a run that never reached the target speed
  /// counts as DNF rather than leaving the rider waiting indefinitely.
  final int dnfSeconds;
}
