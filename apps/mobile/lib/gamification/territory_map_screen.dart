import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../auth/current_user.dart';
import '../data/data_events.dart';
import '../friends/friend_models.dart';
import '../sync/sync_service.dart';
import '../theme/app_theme.dart';
import '../theme/dark_tile_layer.dart';
import '../theme/ph_icons.dart';
import 'territory.dart';
import 'territory_map_cell.dart';

enum _Scope { global, friends }

/// A world map of every rider's claimed territory. Drawn as a chain of
/// flat-topped hexagons tracing the roads you've actually ridden
/// (gamification/territory.dart). Identity is now stated once, in the
/// bottom sheet's legend, rather than by a per-rider hue on the map
/// itself — see the design handoff §4: a hexagon reads as yours,
/// a friend's, or someone else's, nothing more granular. Only aggregate
/// cell ownership is fetched — see get_territory_map()'s comment in
/// supabase/leaderboard.sql for why this deliberately can't show
/// anyone's actual route.
///
/// The basemap is CARTO's Dark Matter tile set (free, no API key, same
/// "fine at this scale" caveat as the OSM/Esri tiles trip_detail_screen
/// already uses) — Nocturne is dark-only, so there's no Positron switch
/// to make anymore.
///
/// Two scopes, same Global/Friends split as leaderboard/leaderboard_screen.dart:
/// every rider who hasn't opted out (Account's "Show me on leaderboards"
/// toggle), or just you and your accepted friends.
class TerritoryMapScreen extends StatefulWidget {
  const TerritoryMapScreen({super.key});

  @override
  State<TerritoryMapScreen> createState() => _TerritoryMapScreenState();
}

class _TerritoryMapScreenState extends State<TerritoryMapScreen> {
  final _mapController = MapController();

  List<TerritoryMapCell>? _cells;
  Set<String> _friendIds = {};
  String? _myUserId;
  _Scope _scope = _Scope.global;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // This screen lives inside HomeShell's Map tab navigator, mounted for
    // the app's lifetime — without this, a trip recorded (and synced)
    // after the tab's first load would never appear until the user
    // thought to switch scope. See data/data_events.dart.
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
    // Only needed to tell "friend" from "other" while in Global scope —
    // in Friends scope every non-mine cell is already a friend's.
    final friends = _scope == _Scope.global ? await SyncService.instance.fetchFriends() : const <RiderSummary>[];
    if (!mounted) return;
    setState(() {
      _myUserId = myUserId;
      _cells = cells;
      _friendIds = {for (final f in friends) f.userId};
      _loading = false;
    });
  }

  void _setScope(_Scope scope) {
    if (scope == _scope) return;
    setState(() => _scope = scope);
    _load();
  }

  Future<void> _locate() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      _mapController.move(LatLng(pos.latitude, pos.longitude), 14);
    } catch (_) {
      // No permission / no fix — the crosshair simply does nothing this
      // tap, same as it would with no signal on any map app.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (CurrentUser.instance.isGuest) {
      return const Scaffold(
        backgroundColor: Noct.bg,
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Sign in to see conquered territory across all riders.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Noct.n500, fontSize: 13),
            ),
          ),
        ),
      );
    }

    return Scaffold(backgroundColor: Noct.canvas, body: _loading ? const Center(child: CircularProgressIndicator()) : _buildMap());
  }

  Widget _buildMap() {
    final cells = _cells ?? const [];
    final hasCells = cells.isNotEmpty;

    final polygons = cells.map((cell) {
      final isMine = cell.userId == _myUserId;
      final isFriend = !isMine && _friendIds.contains(cell.userId);
      final Color fill;
      final Color stroke;
      final double strokeWidth;
      if (isMine) {
        fill = Noct.accent.withValues(alpha: 0.35);
        stroke = Noct.accent;
        strokeWidth = 1.2;
      } else if (isFriend) {
        fill = Noct.n400.withValues(alpha: 0.18);
        stroke = Noct.n400;
        strokeWidth = 1;
      } else {
        fill = Noct.n600.withValues(alpha: 0.16);
        stroke = Noct.n600;
        strokeWidth = 1;
      }
      return Polygon(points: cellPolygonFor(cell.cellKey), color: fill, borderColor: stroke, borderStrokeWidth: strokeWidth);
    }).toList();

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _mapController,
          options: hasCells
              ? MapOptions(
                  initialCameraFit: CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints([for (final cell in cells) ...cellPolygonFor(cell.cellKey)]),
                    padding: const EdgeInsets.all(32),
                  ),
                )
              : const MapOptions(initialCenter: LatLng(20, 0), initialZoom: 2),
          children: [
            const DarkTileLayer(),
            PolygonLayer(polygons: polygons),
          ],
        ),
        Positioned(
          // The map is deliberately full-bleed under the status bar/notch,
          // but these controls have to be real tap targets — without the
          // safe-area inset they render (and hit-test) right under the
          // system status bar, unreachable.
          top: 14 + MediaQuery.paddingOf(context).top,
          left: 16,
          right: 16,
          child: Row(
            children: [
              _ScopeSwitch(scope: _scope, onChanged: _setScope),
              const Spacer(),
              _FloatingChip(icon: Ph.crosshair, onTap: _locate),
            ],
          ),
        ),
        if (hasCells)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _TerritorySheet(cells: cells, myUserId: _myUserId, friendIds: _friendIds, scope: _scope),
          )
        else
          Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Text(
              _scope == _Scope.global
                  ? 'No territory claimed yet — this fills in as riders record trips.'
                  : 'No friends\' territory yet — add a friend from the Ranks tab, or '
                        'check that "Show me on leaderboards" is on for both of you.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Noct.n400, fontSize: 13, height: 1.5),
            ),
          ),
      ],
    );
  }
}

class _ScopeSwitch extends StatelessWidget {
  const _ScopeSwitch({required this.scope, required this.onChanged});
  final _Scope scope;
  final ValueChanged<_Scope> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: Noct.bg.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(Noct.rMd)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [_option(_Scope.global, 'Global'), _option(_Scope.friends, 'Friends')],
      ),
    );
  }

  Widget _option(_Scope value, String label) {
    final selected = value == scope;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Noct.a900 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12.5, color: selected ? Noct.a100 : Noct.n400, fontWeight: FontWeight.w400),
        ),
      ),
    );
  }
}

class _FloatingChip extends StatelessWidget {
  const _FloatingChip({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Noct.rMd),
      child: Material(
        color: Noct.bg.withValues(alpha: 0.75),
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(9), child: Icon(icon, size: 17, color: Noct.n300)),
        ),
      ),
    );
  }
}

class _TerritorySheet extends StatelessWidget {
  const _TerritorySheet({required this.cells, required this.myUserId, required this.friendIds, required this.scope});

  final List<TerritoryMapCell> cells;
  final String? myUserId;
  final Set<String> friendIds;
  final _Scope scope;

  @override
  Widget build(BuildContext context) {
    final mine = cells.where((c) => c.userId == myUserId).length;
    final friends = cells.where((c) => c.userId != myUserId && friendIds.contains(c.userId)).length;
    final others = cells.length - mine - friends;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Noct.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Noct.rLg)),
        boxShadow: Noct.shadowMd,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 34,
                height: 3,
                decoration: BoxDecoration(color: Noct.n700, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$mine', style: Noct.stat(38)),
                  const TextSpan(
                    text: ' areas claimed',
                    style: TextStyle(fontSize: 12.5, color: Noct.n400, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Row(
                  children: [
                    Expanded(flex: mine, child: const ColoredBox(color: Noct.accent, child: SizedBox.expand())),
                    Expanded(flex: friends, child: const ColoredBox(color: Noct.n400, child: SizedBox.expand())),
                    Expanded(flex: others > 0 ? others : 1, child: ColoredBox(color: others > 0 ? Noct.n600 : Noct.n900)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Share of the visible map',
              style: TextStyle(fontSize: 10.5, color: Noct.n500, fontWeight: FontWeight.w400),
            ),
            const SizedBox(height: 14),
            _legendRow('You', Noct.accent, mine, Noct.text),
            if (friends > 0) _legendRow('Friends', Noct.n400, friends, Noct.n300),
            if (others > 0) _legendRow('Others', Noct.n600, others, Noct.n300),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _legendRow(String name, Color swatch, int value, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: swatch, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 11),
          Expanded(child: Text(name, style: TextStyle(fontSize: 12.5, color: textColor, fontWeight: FontWeight.w400))),
          Text('$value', style: const TextStyle(fontSize: 12.5, color: Noct.n400, fontFeatures: [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}
