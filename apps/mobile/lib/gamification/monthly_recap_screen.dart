import 'package:flutter/material.dart';

import '../auth/current_user.dart';
import '../data/models/trip.dart';
import '../data/repositories/gamification_repository.dart';
import '../data/repositories/trip_repository.dart';
import 'trophies.dart';

/// A month-windowed slice of the same all-time stats the Account tab and
/// leaderboard already show — no new data, just
/// TripRepository.listForUserInRange/GamificationRepository's range
/// queries instead of the all-time ones. Works for guests too (it's all
/// local, keyed by CurrentUser.instance.id() regardless of sign-in
/// state) — unlike the leaderboard/friends screens, nothing here needs
/// another user's data.
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

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    final totalDistance = _trips.fold<double>(0, (sum, t) => sum + t.distanceMeters);
    final totalDuration = _trips.fold<int>(0, (sum, t) => sum + t.durationSeconds);
    final longest = _trips.fold<double>(0, (max, t) => t.distanceMeters > max ? t.distanceMeters : max);

    return Scaffold(
      appBar: AppBar(title: const Text('Monthly recap')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shiftMonth(-1)),
                Text(
                  '${_monthNames[_month.month - 1]} ${_month.year}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
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
                      child: Text('No trips recorded this month.', textAlign: TextAlign.center),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.6,
                        children: [
                          _RecapStat('Distance', '${(totalDistance / 1000).toStringAsFixed(0)} km'),
                          _RecapStat('Trips', '${_trips.length}'),
                          _RecapStat('Time driving', _fmtDuration(totalDuration)),
                          _RecapStat('Longest trip', '${(longest / 1000).toStringAsFixed(0)} km'),
                          _RecapStat('New territory', '$_newTerritoryCells areas'),
                          _RecapStat('Trophies earned', '${_trophiesEarned.length}'),
                        ],
                      ),
                      if (_trophiesEarned.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(top: 24, bottom: 8),
                          child: Text(
                            'Trophies this month',
                            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                          ),
                        ),
                        ..._trophiesEarned.map(
                          (t) => ListTile(
                            leading: Icon(t.icon, color: Colors.amber),
                            title: Text(t.name),
                            subtitle: Text(t.description),
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

class _RecapStat extends StatelessWidget {
  const _RecapStat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
