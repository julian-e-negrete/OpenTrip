import 'package:flutter/material.dart';

import '../auth/current_user.dart';
import '../sync/sync_service.dart';
import 'leaderboard_entry.dart';

/// Cross-user rankings across TripRank's four categories (distance,
/// longest single drive, territory explored, trophies) — deliberately
/// not speed-based, matching README.md's "why this exists". Pulled
/// on-demand (pull-to-refresh), not live — unlike vehicles/trips, this
/// isn't part of the Realtime subscription in sync/sync_service.dart,
/// since a leaderboard being a few minutes stale doesn't matter the way
/// "did my own trip save" does.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<LeaderboardEntry>? _entries;
  String? _myUserId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final myUserId = await CurrentUser.instance.id();
    final entries = await SyncService.instance.fetchLeaderboard();
    if (!mounted) return;
    setState(() {
      _myUserId = myUserId;
      _entries = entries;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (CurrentUser.instance.isGuest) {
      return Scaffold(
        appBar: AppBar(title: const Text('Leaderboard')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Sign in to see how you rank against other riders.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Leaderboard'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Distance'),
              Tab(text: 'Longest drive'),
              Tab(text: 'Territory'),
              Tab(text: 'Trophies'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: TabBarView(
                  children: [
                    _RankedList(entries: _entries!, myUserId: _myUserId, category: LeaderboardCategory.distance),
                    _RankedList(
                      entries: _entries!,
                      myUserId: _myUserId,
                      category: LeaderboardCategory.longestDrive,
                    ),
                    _RankedList(
                      entries: _entries!,
                      myUserId: _myUserId,
                      category: LeaderboardCategory.territory,
                    ),
                    _RankedList(entries: _entries!, myUserId: _myUserId, category: LeaderboardCategory.trophies),
                  ],
                ),
              ),
      ),
    );
  }
}

class _RankedList extends StatelessWidget {
  const _RankedList({required this.entries, required this.myUserId, required this.category});

  final List<LeaderboardEntry> entries;
  final String? myUserId;
  final LeaderboardCategory category;

  double _valueFor(LeaderboardEntry e) => switch (category) {
    LeaderboardCategory.distance => e.totalDistanceMeters,
    LeaderboardCategory.longestDrive => e.longestDriveMeters,
    LeaderboardCategory.territory => e.territoryCells.toDouble(),
    LeaderboardCategory.trophies => e.trophyCount.toDouble(),
  };

  String _formatValue(LeaderboardEntry e) => switch (category) {
    LeaderboardCategory.distance => '${(e.totalDistanceMeters / 1000).toStringAsFixed(0)} km',
    LeaderboardCategory.longestDrive => '${(e.longestDriveMeters / 1000).toStringAsFixed(0)} km',
    LeaderboardCategory.territory => '${e.territoryCells} areas',
    LeaderboardCategory.trophies => '${e.trophyCount} 🏆',
  };

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No leaderboard data yet — this fills in as riders record trips.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final ranked = List<LeaderboardEntry>.of(entries)..sort((a, b) => _valueFor(b).compareTo(_valueFor(a)));

    return ListView.builder(
      itemCount: ranked.length,
      itemBuilder: (context, i) {
        final entry = ranked[i];
        final isMe = entry.userId == myUserId;
        return ListTile(
          tileColor: isMe ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
          leading: CircleAvatar(child: Text('${i + 1}')),
          title: Text(entry.displayName),
          trailing: Text(_formatValue(entry), style: const TextStyle(fontWeight: FontWeight.bold)),
        );
      },
    );
  }
}
