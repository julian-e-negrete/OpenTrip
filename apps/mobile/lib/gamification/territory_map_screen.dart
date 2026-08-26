import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../auth/current_user.dart';
import '../data/data_events.dart';
import '../friends/friends_screen.dart';
import '../sync/sync_service.dart';
import 'territory.dart';
import 'territory_map_cell.dart';

enum _Scope { global, friends }

/// A world map of every rider's claimed territory — the "conquered
/// zones" view OpenTrip shows alongside its leaderboard. Drawn as a
/// chain of flat-topped hexagons tracing the roads you've actually
/// ridden (gamification/territory.dart), the same "conquer the map"
/// look TripRank itself uses, rather than either of this screen's two
/// earlier passes: a checkerboard of bordered rectangles, then an
/// extruded-column look copying deck.gl's HexagonLayer. The column
/// version looked right for scattered, sparse density data (what
/// HexagonLayer is normally used for) but broke down for territory,
/// which is dense and contiguous — leaning columns on cells that touch
/// their neighbors on every side collided into each other. Going flat
/// removes that problem entirely, and matches the actual reference this
/// was chasing.
///
/// Your own territory is drawn in the app's coral accent; everyone
/// else's in a color derived from their user id (stable across screen
/// loads, so the same rider always reads as the same color). Only
/// aggregate cell ownership is fetched — see get_territory_map()'s
/// comment in supabase/leaderboard.sql for why this deliberately can't
/// show anyone's actual route.
///
/// The basemap switches between CARTO's Dark Matter and Positron tile
/// sets by the app's current brightness (dark/light, following system —
/// see theme/app_theme.dart) instead of OpenStreetMap's default colorful
/// street style. Both CARTO sets are free, no API key, same "fine at
/// this scale, not for heavy production traffic" caveat as the OSM/Esri
/// tiles trip_detail_screen.dart already uses.
///
/// Two scopes, same Global/Friends split as leaderboard/leaderboard_screen.dart:
/// every rider who hasn't opted out (Account tab's "Show me on
/// leaderboards" toggle), or just you and your accepted friends (see
/// friends/friends_screen.dart, reachable via the people icon here or on
/// the Trips tab).
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
    // This screen lives inside HomeShell's IndexedStack, so initState only
    // ever runs once — without this, a trip recorded (and synced) after
    // the tab's first load would never appear until the user thought to
    // pull-to-refresh. See data/data_events.dart.
    DataEvents.instance.listenable.addListener(_load);
  }

  @override
  void dispose() {
    DataEvents.instance.listenable.removeListener(_load);
    super.dispose();
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
    return HSVColor.fromAHSV(1, hue, 0.75, 0.92).toColor();
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
        actions: [
          IconButton(
            icon: const Icon(Icons.people_outline),
            tooltip: 'Friends',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FriendsScreen()),
            ),
          ),
        ],
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
          : 'No friends\' territory yet — add a friend using the people icon '
                'above, or check that "Show me on leaderboards" is on for both of you.';
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ],
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final allBounds = LatLngBounds.fromPoints([for (final cell in cells) ...cellPolygonFor(cell.cellKey)]);

    final polygons = cells.map((cell) {
      final isMine = cell.userId == _myUserId;
      final color = isMine ? scheme.primary : _colorForUser(cell.userId);
      return Polygon(
        points: cellPolygonFor(cell.cellKey),
        color: color.withValues(alpha: 0.4),
        borderColor: color.withValues(alpha: 0.9),
        borderStrokeWidth: 1.5,
      );
    }).toList();

    final riders = <String, String>{for (final c in cells) c.userId: c.displayName};
    final riderOrder = riders.keys.toList()
      ..sort((a, b) {
        if (a == _myUserId) return -1;
        if (b == _myUserId) return 1;
        return 0;
      });

    return Column(
      children: [
        Expanded(
          child: FlutterMap(
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(bounds: allBounds, padding: const EdgeInsets.all(32)),
            ),
            children: [
              TileLayer(
                urlTemplate: isDark
                    ? 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                    : 'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                userAgentPackageName: 'co.opentrip.opentrip_mobile',
              ),
              PolygonLayer(polygons: polygons),
            ],
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: riderOrder.map((userId) {
              final isMine = userId == _myUserId;
              final color = isMine ? scheme.primary : _colorForUser(userId);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    border: Border.all(color: scheme.outline),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isMine ? '${riders[userId]} (you)' : riders[userId]!,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isMine ? FontWeight.w800 : FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
