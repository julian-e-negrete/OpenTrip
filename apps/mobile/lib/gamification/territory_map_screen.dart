import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../auth/current_user.dart';
import '../sync/sync_service.dart';
import 'territory.dart';
import 'territory_map_cell.dart';

enum _Scope { global, friends }

/// A world map of every rider's claimed territory — the "conquered
/// zones" view OpenTrip shows alongside its leaderboard. Rendered as a
/// soft heat glow, not a grid of flat rectangles: each ~1.1km cell
/// (gamification/territory.dart) you've ridden through contributes a
/// blob of color, and blobs from the same rider blend additively where
/// they overlap (see [_TerritoryHeatLayer]) — so a cell you've crossed
/// once glows faint and one you cross on every commute glows solid,
/// intensity driven by territory_cells.visit_count
/// (data/repositories/gamification_repository.dart). Your own territory
/// is drawn in the app's coral accent; everyone else's in a color
/// derived from their user id (stable across screen loads, so the same
/// rider always reads as the same color). Only aggregate cell ownership
/// + visit count is fetched — see get_territory_map()'s comment in
/// supabase/leaderboard.sql for why this deliberately can't show
/// anyone's actual route.
///
/// The basemap switches between CARTO's Dark Matter and Positron tile
/// sets by the app's current brightness (dark/light, following system —
/// see theme/app_theme.dart) instead of OpenStreetMap's default colorful
/// street style, which fought the heat glow for attention and didn't sit
/// well with either theme. Both CARTO sets are free, no API key, same
/// "fine at this scale, not for heavy production traffic" caveat as the
/// OSM/Esri tiles trip_detail_screen.dart already uses.
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
  /// server-assigned color column. Pushed toward high saturation/value so
  /// it still pops as a soft glow against the dark or light CARTO
  /// basemap, not just as a hard-edged fill.
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

    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final allBounds = LatLngBounds.fromPoints([
      for (final cell in cells) ...() {
        final b = cellBoundsFor(cell.cellKey);
        return [b.southWest, b.northEast];
      }(),
    ]);

    final byUser = <String, List<TerritoryMapCell>>{};
    for (final cell in cells) {
      byUser.putIfAbsent(cell.userId, () => []).add(cell);
    }

    // Draw everyone else first, "you" last — your own territory should
    // sit on top where it overlaps someone else's.
    final userOrder = byUser.keys.toList()
      ..sort((a, b) {
        if (a == _myUserId) return 1;
        if (b == _myUserId) return -1;
        return 0;
      });

    final groups = userOrder.map((userId) {
      final isMine = userId == _myUserId;
      return _HeatGroup(color: isMine ? scheme.primary : _colorForUser(userId), cells: byUser[userId]!);
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
              _TerritoryHeatLayer(groups: groups),
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

class _HeatGroup {
  const _HeatGroup({required this.color, required this.cells});
  final Color color;
  final List<TerritoryMapCell> cells;
}

/// Paints [_HeatGroup]s as soft, additively-blended glows instead of flat
/// rectangles. Each cell becomes a radial-gradient blob centered on the
/// cell and sized to overlap its neighbors, so a contiguous ridden area
/// reads as one continuous field of color rather than a checkerboard of
/// grid squares. Blobs are grouped per rider and composited on their own
/// layer with [BlendMode.plus]: overlapping cells from the *same* rider
/// brighten together (more visits = a hotter glow), while different
/// riders' layers still composite normally against each other and the
/// basemap beneath.
///
/// Mirrors flutter_map's own [CircleLayer]/[CirclePainter] plumbing
/// (camera-aware [CustomPaint] wrapped in [MobileLayerTransformer]) since
/// there's no built-in heatmap layer in flutter_map — this is that layer,
/// purpose-built for cell-based territory instead of arbitrary points.
class _TerritoryHeatLayer extends StatelessWidget {
  const _TerritoryHeatLayer({required this.groups});
  final List<_HeatGroup> groups;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _HeatPainter(camera: camera, groups: groups),
        size: Size(camera.size.x, camera.size.y),
        isComplex: true,
      ),
    );
  }
}

class _HeatPainter extends CustomPainter {
  _HeatPainter({required this.camera, required this.groups});

  final MapCamera camera;
  final List<_HeatGroup> groups;

  /// Visits at or above this many light up at full intensity — a
  /// deliberately low bar (a well-worn daily-commute cell) rather than
  /// requiring dozens of passes to ever look "solid."
  static const _capVisits = 6;
  static const _minAlpha = 0.22;
  static const _maxAlpha = 0.85;
  static const _blobScale = 1.7;
  static const _minBlobRadius = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    for (final group in groups) {
      // A fresh transparent layer per rider so their own overlapping
      // cells can brighten together via BlendMode.plus without washing
      // out or blending into a different rider's color underneath.
      canvas.saveLayer(Offset.zero & size, Paint());
      for (final cell in group.cells) {
        final bounds = cellBoundsFor(cell.cellKey);
        final nw = camera.getOffsetFromOrigin(bounds.northWest);
        final se = camera.getOffsetFromOrigin(bounds.southEast);
        final center = Offset((nw.dx + se.dx) / 2, (nw.dy + se.dy) / 2);
        final halfWidth = (se.dx - nw.dx).abs() / 2;
        final halfHeight = (se.dy - nw.dy).abs() / 2;
        final radius = math.max(math.max(halfWidth, halfHeight) * _blobScale, _minBlobRadius);
        final ratio = (cell.visitCount / _capVisits).clamp(0.0, 1.0);
        final alpha = _minAlpha + (_maxAlpha - _minAlpha) * ratio;

        final paint = Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [group.color.withValues(alpha: alpha), group.color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius));
        canvas.drawCircle(center, radius, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _HeatPainter oldDelegate) =>
      groups != oldDelegate.groups || camera != oldDelegate.camera;
}
