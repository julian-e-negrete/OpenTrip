import 'package:flutter/material.dart';

import '../auth/current_user.dart';
import '../friends/friends_screen.dart';
import '../sync/sync_service.dart';
import '../theme/app_theme.dart';
import '../theme/layout_prefs.dart';
import '../theme/num_fmt.dart';
import '../theme/ph_icons.dart';
import '../theme/primitives.dart';
import 'leaderboard_entry.dart';

enum _Scope { global, friends }

/// Cross-user rankings across TripRank's four categories (distance,
/// longest single drive, territory explored, trophies) — originally
/// deliberately not speed-based, matching README.md's "why this exists"
/// (TripRank-parity, not a racing app). Racing stats (best 0-60/0-180
/// km/h, top speed) were added later as explicit secondary columns on
/// every row — see [_RankRow] — rather than as a fifth primary category,
/// since ranking riders by raw speed cuts against that original posture
/// even though showing the numbers doesn't. Pulled on-demand, not live —
/// a leaderboard being a few minutes stale doesn't matter the way "did
/// my own trip save" does.
///
/// Two scopes, matching TripRank's "global & friends leaderboards":
/// every rider who hasn't opted out (Account's "Show me on
/// leaderboards" toggle), or just you and your accepted friends.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<LeaderboardEntry>? _entries;
  String? _myUserId;
  _Scope _scope = _Scope.global;
  LeaderboardCategory _category = LeaderboardCategory.distance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final myUserId = await CurrentUser.instance.id();
    final entries = _scope == _Scope.global
        ? await SyncService.instance.fetchLeaderboard()
        : await SyncService.instance.fetchFriendsLeaderboard();
    if (!mounted) return;
    setState(() {
      _myUserId = myUserId;
      _entries = entries;
      _loading = false;
    });
  }

  void _setScope(_Scope scope) {
    if (scope == _scope) return;
    setState(() => _scope = scope);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (CurrentUser.instance.isGuest) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Ranks'),
          actions: [
            IconButton(
              icon: const Icon(Ph.users),
              tooltip: 'Friends',
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FriendsScreen())),
            ),
          ],
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Sign in to see how you rank against other riders.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Noct.n500, fontSize: 13),
            ),
          ),
        ),
      );
    }

    return ListenableBuilder(
      listenable: LayoutPrefs.instance,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Ranks'),
            actions: [
              IconButton(
                icon: const Icon(Ph.users),
                tooltip: 'Friends',
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FriendsScreen()));
                  if (mounted) _load();
                },
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
                        child: _BorderedScopeSwitch(scope: _scope, onChanged: _setScope),
                      ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Row(
                          children: [
                            for (final c in LeaderboardCategory.values)
                              Padding(
                                padding: const EdgeInsets.only(right: 7),
                                child: _CategoryChip(
                                  label: _categoryLabel(c),
                                  selected: c == _category,
                                  onTap: () => setState(() => _category = c),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _RankedContent(entries: _entries ?? const [], myUserId: _myUserId, category: _category, scope: _scope),
                    ],
                  ),
                ),
        );
      },
    );
  }

  String _categoryLabel(LeaderboardCategory c) => switch (c) {
    LeaderboardCategory.distance => 'Distance',
    LeaderboardCategory.longestDrive => 'Longest',
    LeaderboardCategory.territory => 'Territory',
    LeaderboardCategory.trophies => 'Trophies',
  };
}

class _BorderedScopeSwitch extends StatelessWidget {
  const _BorderedScopeSwitch({required this.scope, required this.onChanged});
  final _Scope scope;
  final ValueChanged<_Scope> onChanged;

  @override
  Widget build(BuildContext context) {
    return NoctSegmentedControl<_Scope>(
      value: scope,
      onChanged: onChanged,
      options: const [(_Scope.global, 'Global'), (_Scope.friends, 'Friends')],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Noct.rMd),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          overlayColor: WidgetStatePropertyAll(Noct.accent.withValues(alpha: 0.05)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? Noct.a900 : Colors.transparent,
              borderRadius: BorderRadius.circular(Noct.rMd),
              border: Border.all(color: selected ? Noct.a700 : Noct.divider),
            ),
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: selected ? Noct.a100 : Noct.n400, fontWeight: FontWeight.w400),
            ),
          ),
        ),
      ),
    );
  }
}

double _valueFor(LeaderboardEntry e, LeaderboardCategory category) => switch (category) {
  LeaderboardCategory.distance => e.totalDistanceMeters,
  LeaderboardCategory.longestDrive => e.longestDriveMeters,
  LeaderboardCategory.territory => e.territoryCells.toDouble(),
  LeaderboardCategory.trophies => e.trophyCount.toDouble(),
};

String _formatValue(LeaderboardEntry e, LeaderboardCategory category) => switch (category) {
  LeaderboardCategory.distance => '${fmtThousands((e.totalDistanceMeters / 1000).round())} km',
  LeaderboardCategory.longestDrive => '${fmtThousands((e.longestDriveMeters / 1000).round())} km',
  LeaderboardCategory.territory => fmtThousands(e.territoryCells),
  LeaderboardCategory.trophies => fmtThousands(e.trophyCount),
};

class _RankedContent extends StatelessWidget {
  const _RankedContent({required this.entries, required this.myUserId, required this.category, required this.scope});

  final List<LeaderboardEntry> entries;
  final String? myUserId;
  final LeaderboardCategory category;
  final _Scope scope;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      final message = scope == _Scope.global
          ? 'No leaderboard data yet — this fills in as riders record trips.'
          : 'No friends ranked yet — add a friend from the people icon above, '
                'or check that "Show me on leaderboards" is on for both of you.';
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Noct.n500, fontSize: 13)),
      );
    }

    final ranked = List<LeaderboardEntry>.of(entries)
      ..sort((a, b) => _valueFor(b, category).compareTo(_valueFor(a, category)));
    final max = ranked.map((e) => _valueFor(e, category)).fold<double>(0, (m, v) => v > m ? v : m);

    // "The one who got the fastest speed of all" — a single visual
    // callout on whichever row (among those currently shown) actually
    // holds the highest top speed, independent of the primary sort/
    // category above.
    String? fastestUserId;
    double? fastestTopSpeed;
    for (final e in ranked) {
      final topSpeed = e.topSpeedKph;
      if (topSpeed != null && (fastestTopSpeed == null || topSpeed > fastestTopSpeed)) {
        fastestTopSpeed = topSpeed;
        fastestUserId = e.userId;
      }
    }

    return Column(
      children: [
        if (LayoutPrefs.instance.ranks == RanksVariant.podium && ranked.length >= 3)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: _Podium(top3: ranked.take(3).toList(), myUserId: myUserId, category: category),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            children: [
              for (var i = 0; i < ranked.length; i++)
                _RankRow(
                  rank: i + 1,
                  entry: ranked[i],
                  isMe: ranked[i].userId == myUserId,
                  fraction: max <= 0 ? 0 : _valueFor(ranked[i], category) / max,
                  valueLabel: _formatValue(ranked[i], category),
                  isFastest: ranked[i].userId == fastestUserId,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.entry,
    required this.isMe,
    required this.fraction,
    required this.valueLabel,
    required this.isFastest,
  });

  final int rank;
  final LeaderboardEntry entry;
  final bool isMe;
  final double fraction;
  final String valueLabel;

  /// Whether this rider holds the single highest top speed among
  /// everyone currently shown — see _RankedContent's fastestUserId.
  final bool isFastest;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isMe ? Noct.a900 : Noct.surface,
        borderRadius: BorderRadius.circular(Noct.rMd),
        border: Border.all(color: isMe ? Noct.a700 : Noct.n800),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction.clamp(0.0, 1.0),
              child: ColoredBox(color: isMe ? Noct.accent.withValues(alpha: 0.22) : Noct.n500.withValues(alpha: 0.10)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 16,
                      child: Text(
                        rank.toString().padLeft(2, '0'),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Noct.n500,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isMe ? 'You' : entry.displayName,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: isMe ? Noct.a100 : Noct.text,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      valueLabel,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: Noct.text,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 26),
                  child: _RacingStatsLine(entry: entry, isFastest: isFastest),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The three secondary racing stats every row shows regardless of which
/// primary category is active — best 0-60, best 0-180, top speed —
/// plus a small highlight on whichever rider holds the single fastest
/// top speed among everyone currently shown.
class _RacingStatsLine extends StatelessWidget {
  const _RacingStatsLine({required this.entry, required this.isFastest});

  final LeaderboardEntry entry;
  final bool isFastest;

  static String _seconds(double? v) => v == null ? '—' : '${v.toStringAsFixed(2)}s';

  @override
  Widget build(BuildContext context) {
    final topSpeedColor = isFastest ? Noct.a300 : Noct.n400;
    final topSpeed = entry.topSpeedKph;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '0-60 ${_seconds(entry.best0To60Seconds)}',
          style: const TextStyle(fontSize: 11, color: Noct.n500, fontFeatures: [FontFeature.tabularFigures()]),
        ),
        const Text('  ·  ', style: TextStyle(fontSize: 11, color: Noct.n700)),
        Text(
          '0-180 ${_seconds(entry.best0To180Seconds)}',
          style: const TextStyle(fontSize: 11, color: Noct.n500, fontFeatures: [FontFeature.tabularFigures()]),
        ),
        const Text('  ·  ', style: TextStyle(fontSize: 11, color: Noct.n700)),
        if (isFastest) ...[
          Icon(Ph.lightning, size: 11, color: topSpeedColor),
          const SizedBox(width: 2),
        ],
        Text(
          topSpeed == null ? 'Top —' : 'Top ${topSpeed.toStringAsFixed(0)} km/h',
          style: TextStyle(
            fontSize: 11,
            color: topSpeedColor,
            fontWeight: isFastest ? FontWeight.w500 : FontWeight.w400,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.top3, required this.myUserId, required this.category});
  final List<LeaderboardEntry> top3;
  final String? myUserId;
  final LeaderboardCategory category;

  @override
  Widget build(BuildContext context) {
    final second = top3[1];
    final first = top3[0];
    final third = top3[2];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: _place(second, 2, false)),
        const SizedBox(width: 9),
        Expanded(child: _place(first, 1, true)),
        const SizedBox(width: 9),
        Expanded(child: _place(third, 3, false)),
      ],
    );
  }

  Widget _place(LeaderboardEntry e, int rank, bool isFirst) {
    final isMe = e.userId == myUserId;
    return Container(
      padding: EdgeInsets.all(isFirst ? 20 : (rank == 2 ? 14 : 12)),
      decoration: BoxDecoration(
        color: isFirst ? Noct.a900 : Noct.surface,
        borderRadius: BorderRadius.circular(Noct.rMd),
        border: Border.all(color: isFirst ? Noct.a700 : Noct.n800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            rank.toString().padLeft(2, '0'),
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.0,
              color: isFirst ? Noct.a300 : Noct.n500,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isMe ? 'You' : e.displayName,
            style: TextStyle(fontSize: 12, color: isFirst ? Noct.a100 : Noct.text, fontWeight: FontWeight.w400),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            _formatValue(e, category),
            style: TextStyle(
              fontSize: isFirst ? 22 : 18,
              fontWeight: FontWeight.w500,
              color: isFirst ? Noct.a100 : Noct.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
