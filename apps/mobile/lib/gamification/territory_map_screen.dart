import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../auth/current_user.dart';
import '../sync/sync_service.dart';
import 'territory.dart';
import 'territory_map_cell.dart';

enum _Scope { global, friends }

/// A world map of every rider's claimed territory — the "conquered
/// zones" view TripRank shows alongside its leaderboard. Each filled
/// rectangle is one ~1.1km grid cell (gamification/territory.dart) that
/// someone has ridden through at least once; your own cells are drawn in
/// a fixed highlight color, everyone else's in a color derived from
/// their user id (stable across screen loads, so the same rider always
/// reads as the same color). Only aggregate cell ownership is fetched —
/// see get_territory_map()'s comment in supabase/leaderboard.sql for why
/// this deliberately can't show anyone's actual route.
///
/// Two scopes, same Global/Friends split as leaderboard/leaderboard_screen.dart:
/// every rider who hasn't opted out (Account tab's "Show me on
/// leaderboards" toggle), or just you and your accepted friends (see
/// friends/friends_screen.dart, reachable from the Leaderboard tab).
class TerritoryMapScreen extends StatefulWidget {
  const TerritoryMapScreen({super.key});

  @override
  State<TerritoryMapScreen> createState() => _TerritoryMapScreenState();
}

class _TerritoryMapScreenState extends State<TerritoryMapScreen> {
  List<TerritoryMapCell>? _cells;
  String? _myUserId;
  _Scope _scope = _Scope.global;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final myUserId = await CurrentUser.instance.id();
    final cells = _scope == _Scope.global
        ? await SyncService.instance.fetchTerritoryMap()
        : await SyncService.instance.fetchFriendsTerritoryMap();
    if (!mounted) return;
    setState(() {
      _myUserId = myUserId;
      _cells = cells;
      _loading = false;
    });
  }

  void _setScope(_Scope scope) {
    if (scope == _scope) return;
    setState(() => _scope = scope);
    _load();
  }

  /// A stable, reasonably distinct color per rider — derived from their
  /// user id so it doesn't shuffle between loads, without needing a
  /// server-assigned color column.
  Color _colorForUser(String userId) {
    final hue = (userId.hashCode.abs() % 360).toDouble();
    return HSVColor.fromAHSV(1, hue, 0.65, 0.85).toColor();
  }

  @override
  Widget build(BuildContext context) {
    if (CurrentUser.instance.isGuest) {
      return Scaffold(
        appBar: AppBar(title: const Text('Territory map')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Sign in to see conquered territory across all riders.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Territory map'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<_Scope>(
              segments: const [
                ButtonSegment(value: _Scope.global, label: Text('Global'), icon: Icon(Icons.public)),
                ButtonSegment(value: _Scope.friends, label: Text('Friends'), icon: Icon(Icons.people)),
              ],
              selected: {_scope},
              onSelectionChanged: (s) => _setScope(s.first),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _buildMap()),
    );
  }

  Widget _buildMap() {
    final cells = _cells ?? const [];
    if (cells.isEmpty) {
      final message = _scope == _Scope.global
          ? 'No territory claimed yet — this fills in as riders record trips.'
          : 'No friends\' territory yet — add a friend from the Leaderboard '
                'tab, or check that "Show me on leaderboards" is on for both of you.';
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ],
      );
    }

    final allBounds = LatLngBounds.fromPoints([
      for (final cell in cells) ...() {
        final b = cellBoundsFor(cell.cellKey);
        return [b.southWest, b.northEast];
      }(),
    ]);

    final polygons = cells.map((cell) {
      final bounds = cellBoundsFor(cell.cellKey);
      final isMine = cell.userId == _myUserId;
      final color = isMine ? Colors.amber : _colorForUser(cell.userId);
      return Polygon(
        points: [bounds.northWest, bounds.northEast, bounds.southEast, bounds.southWest],
        color: color.withValues(alpha: isMine ? 0.55 : 0.35),
        borderColor: color,
        borderStrokeWidth: isMine ? 2 : 1,
      );
    }).toList();

    final riders = <String, String>{for (final c in cells) c.userId: c.displayName};

    return Column(
      children: [
        Expanded(
          child: FlutterMap(
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(bounds: allBounds, padding: const EdgeInsets.all(32)),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'co.opentrip.opentrip_mobile',
              ),
              PolygonLayer(polygons: polygons),
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: riders.entries.map((entry) {
              final isMine = entry.key == _myUserId;
              final color = isMine ? Colors.amber : _colorForUser(entry.key);
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 12, height: 12, color: color),
                    const SizedBox(width: 4),
                    Text(isMine ? '${entry.value} (you)' : entry.value),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
