import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../auth/current_user.dart';
import '../data/models/trip.dart';
import '../data/repositories/gamification_repository.dart';
import '../data/repositories/trip_repository.dart';
import '../theme/app_theme.dart';
import '../theme/date_fmt.dart';
import '../theme/ph_icons.dart';
import '../theme/primitives.dart';
import 'trophies.dart';

/// A month-windowed slice of the same all-time stats the Account tab and
/// leaderboard already show — no new data, just
/// TripRepository.listForUserInRange/GamificationRepository's range
/// queries instead of the all-time ones. Works for guests too.
class MonthlyRecapScreen extends StatefulWidget {
  const MonthlyRecapScreen({super.key});

  @override
  State<MonthlyRecapScreen> createState() => _MonthlyRecapScreenState();
}

class _MonthlyRecapScreenState extends State<MonthlyRecapScreen> {
  late DateTime _month; // always the 1st of some month, local time
  bool _loading = true;

  List<Trip> _trips = [];
  int _newTerritoryCells = 0;
  List<TrophyDefinition> _trophiesEarned = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final userId = await CurrentUser.instance.id();
    final start = _month;
    final end = DateTime(_month.year, _month.month + 1);

    final trips = await TripRepository.instance.listForUserInRange(userId, start: start, end: end);
    final newCells = await GamificationRepository.instance.territoryCellCountInRange(userId, start: start, end: end);
    final trophyKeys = await GamificationRepository.instance.trophyKeysEarnedInRange(userId, start: start, end: end);
    final trophies = trophyKeys
        .map((key) {
          for (final t in trophyCatalog) {
            if (t.key == key) return t;
          }
          return null;
        })
        .whereType<TrophyDefinition>()
        .toList();

    if (!mounted) return;
    setState(() {
      _trips = trips;
      _newTerritoryCells = newCells;
      _trophiesEarned = trophies;
      _loading = false;
    });
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  String _fmtDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours == 0) return '${minutes}m';
    return '${hours}h ${minutes}m';
  }

  Future<void> _share() async {
    final totalKm = (_trips.fold<double>(0, (sum, t) => sum + t.distanceMeters) / 1000).toStringAsFixed(0);
    await SharePlus.instance.share(
      ShareParams(text: 'I rode $totalKm km in ${fmtMonthName(_month)} on OpenTrip 🏍️'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalDistance = _trips.fold<double>(0, (sum, t) => sum + t.distanceMeters);
    final totalDuration = _trips.fold<int>(0, (sum, t) => sum + t.durationSeconds);
    final longest = _trips.fold<double>(0, (max, t) => t.distanceMeters > max ? t.distanceMeters : max);

    return Scaffold(
      appBar: AppBar(
        title: const SizedBox.shrink(),
        actions: [
          IconButton(icon: const Icon(Ph.export_, size: 18, color: Noct.n400), tooltip: 'Share', onPressed: _share),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Ph.caretLeft, size: 16, color: Noct.n500),
                  onPressed: () => _shiftMonth(-1),
                ),
                Text(
                  '${fmtMonthName(_month)} ${_month.year}',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500, letterSpacing: -0.65, color: Noct.text),
                ),
                IconButton(
                  icon: Icon(Ph.caretRight, size: 16, color: _isCurrentMonth ? Noct.n800 : Noct.n500),
                  onPressed: _isCurrentMonth ? null : () => _shiftMonth(1),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _trips.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No trips recorded this month.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Noct.n500, fontSize: 13),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 26),
                    children: [
                      const Text(
                        'YOU RODE',
                        style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: Noct.n500, fontWeight: FontWeight.w400),
                      ),
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: (totalDistance / 1000).toStringAsFixed(0), style: Noct.stat(68)),
                            TextSpan(
                              text: ' km over ${_trips.length} ride${_trips.length == 1 ? '' : 's'}',
                              style: const TextStyle(fontSize: 15, color: Noct.n400, fontWeight: FontWeight.w400),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const FadingRule(),
                      Container(
                        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Noct.n800))),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    decoration: const BoxDecoration(border: Border(right: BorderSide(color: Noct.n800))),
                                    child: _RecapCell('Time driving', _fmtDuration(totalDuration)),
                                  ),
                                ),
                                Expanded(child: _RecapCell('Longest trip', '${(longest / 1000).toStringAsFixed(0)} km')),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      border: Border(right: BorderSide(color: Noct.n800), top: BorderSide(color: Noct.n800)),
                                    ),
                                    child: _RecapCell('New areas', '$_newTerritoryCells', color: Noct.a300),
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: Noct.n800))),
                                    child: _RecapCell('Trophies', '${_trophiesEarned.length}'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const FadingRule(),
                      if (_trophiesEarned.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(top: 24, bottom: 8),
                          child: Text(
                            'EARNED THIS MONTH',
                            style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: Noct.accent, fontWeight: FontWeight.w400),
                          ),
                        ),
                        for (final t in _trophiesEarned)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: NoctPanel(
                              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                              child: Row(
                                children: [
                                  Icon(t.icon, size: 20, color: Noct.a300),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(t.name, style: const TextStyle(fontSize: 13.5, color: Noct.text, fontWeight: FontWeight.w400)),
                                        Text(t.description, style: const TextStyle(fontSize: 11, color: Noct.n500)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _RecapCell extends StatelessWidget {
  const _RecapCell(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: Noct.stat(26, color: color)),
          const SizedBox(height: 4),
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, letterSpacing: 1.2, color: Noct.n500)),
        ],
      ),
    );
  }
}
