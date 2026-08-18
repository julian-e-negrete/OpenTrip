import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../auth/current_user.dart';
import '../sync/sync_service.dart';
import 'territory.dart';
import 'territory_map_cell.dart';

enum _Scope { global, friends }

/// A world map of every rider's claimed territory — the "conquered
/// zones" view OpenTrip shows alongside its leaderboard. Rendered as
/// extruded columns, not flat rectangles: each ~1.1km cell
/// (gamification/territory.dart) you've ridden through rises out of the
/// map as a small 3-faced block (see [_TerritoryColumnLayer]), taller
/// the more times you've crossed it — a cell you've passed once is a
/// low bump, a daily-commute cell stands up like a tower. Height is
/// driven by territory_cells.visit_count
/// (data/repositories/gamification_repository.dart); color is constant
/// per rider, not intensity — your own territory in the app's coral
/// accent, everyone else's in a color derived from their user id
/// (stable across screen loads, so the same rider always reads as the
/// same color). Only aggregate cell ownership + visit count is fetched
/// — see get_territory_map()'s comment in supabase/leaderboard.sql for
/// why this deliberately can't show anyone's actual route.
///
/// This is the second visual pass at this screen — the first drew flat
/// bordered rectangles, the second a soft additive glow. Both read as
/// "a spreadsheet over a map" more than "territory." This version chases
/// the look of deck.gl's HexagonLayer (the extruded-hexbin style behind
/// most Uber-style "3D density" dashboards), faked in 2D screen space
/// since flutter_map has no tiltable 3D camera to do it for real: each
/// cell's true geographic footprint is projected as normal, then a
/// second copy is drawn shifted up-and-right by the column's height,
/// with the gap between the two filled in as the column's front/right
/// walls (see [_ColumnPainter]) — the same "shift the roof, fill the
/// walls" cheat classic isometric icon art uses, not real 3D geometry.
/// It'll look right at today's fixed top-down view but wouldn't tilt
/// correctly if the map ever gained real camera rotation.
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
  /// it still pops as a solid block against the dark or light CARTO
  /// basemap.
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

    // No per-rider grouping needed here (unlike the additive-glow version
    // this replaced) — columns are solid, so correct occlusion just means
    // sorting every column by map position and painting back-to-front,
    // done once inside [_ColumnPainter] itself rather than per-rider.
    final columns = cells.map((cell) {
      final isMine = cell.userId == _myUserId;
      final base = isMine ? scheme.primary : _colorForUser(cell.userId);
      return _TerritoryColumn(
        bounds: cellBoundsFor(cell.cellKey),
        topColor: Color.lerp(base, Colors.white, 0.22)!,
        frontColor: base,
        rightColor: Color.lerp(base, Colors.black, 0.28)!,
        visitCount: cell.visitCount,
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
              _TerritoryColumnLayer(columns: columns),
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

/// One claimed cell, pre-styled: its geographic footprint plus the three
/// shades its column will be drawn in (top/front/right — see
/// [_ColumnPainter]) and how many visits set its height. Shading is
/// computed once here, in [_TerritoryMapScreenState._buildMap], rather
/// than per animation frame inside the painter.
class _TerritoryColumn {
  const _TerritoryColumn({
    required this.bounds,
    required this.topColor,
    required this.frontColor,
    required this.rightColor,
    required this.visitCount,
  });

  final LatLngBounds bounds;
  final Color topColor;
  final Color frontColor;
  final Color rightColor;
  final int visitCount;
}

/// Mirrors flutter_map's own [CircleLayer]/[CirclePainter] plumbing
/// (camera-aware [CustomPaint] wrapped in [MobileLayerTransformer]) since
/// there's no built-in 3D/extrusion layer in flutter_map — this is that
/// layer, purpose-built for cell-based territory columns.
class _TerritoryColumnLayer extends StatelessWidget {
  const _TerritoryColumnLayer({required this.columns});
  final List<_TerritoryColumn> columns;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _ColumnPainter(camera: camera, columns: columns),
        size: Size(camera.size.x, camera.size.y),
        isComplex: true,
      ),
    );
  }
}

/// Paints each [_TerritoryColumn] as a 3-faced block: the cell's real
/// geographic footprint is the base, a second copy of that same
/// rectangle shifted up-and-right by the column's height is the top face,
/// and the gap between the two is filled in as the front and right
/// walls. That shift is the entire "3D" trick — flutter_map's camera
/// can't tilt, so there's no real depth here, just two rectangles and
/// two connecting quads. Faces are flat-shaded (lighter top, base color
/// front, darker right) to sell the illusion, not lit dynamically.
///
/// Column height comes from [_TerritoryColumn.visitCount] scaled by the
/// cell's own on-screen size (not a fixed pixel height) so columns stay
/// proportionate whether you're zoomed into a neighborhood or looking at
/// a whole city.
///
/// Columns are painted back-to-front by their base's screen Y — the
/// same painter's-algorithm ordering real 3D renderers use — so a
/// column further "south" (lower on screen) correctly draws over one
/// further "north" behind it, regardless of which rider owns either
/// cell. There's no per-rider grouping or blending here: every face is
/// fully opaque.
class _ColumnPainter extends CustomPainter {
  _ColumnPainter({required this.camera, required this.columns});

  final MapCamera camera;
  final List<_TerritoryColumn> columns;

  /// Visits at or above this many reach the tallest column height — a
  /// deliberately low bar (a well-worn daily-commute cell) rather than
  /// requiring dozens of passes to ever stand up like a tower.
  static const _capVisits = 6;
  static const _minHeightRatio = 0.35;
  static const _maxHeightRatio = 1.5;
  static const _leanRatio = 0.35;
  static const _maxHeightPx = 140.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);

    final built =
        columns.map((column) {
          final nw = camera.getOffsetFromOrigin(column.bounds.northWest);
          final se = camera.getOffsetFromOrigin(column.bounds.southEast);
          final rect = Rect.fromPoints(nw, se);
          final baseSize = math.max(rect.width, rect.height);
          final ratio = (column.visitCount / _capVisits).clamp(0.0, 1.0);
          final height = (baseSize * (_minHeightRatio + (_maxHeightRatio - _minHeightRatio) * ratio)).clamp(
            4.0,
            _maxHeightPx,
          );
          return (rect: rect, height: height, column: column);
        }).toList()
          ..sort((a, b) => a.rect.bottom.compareTo(b.rect.bottom));

    for (final c in built) {
      final lean = Offset(c.height * _leanRatio, -c.height);
      final topRect = c.rect.shift(lean);

      final frontPath = Path()
        ..moveTo(c.rect.left, c.rect.bottom)
        ..lineTo(topRect.left, topRect.bottom)
        ..lineTo(topRect.right, topRect.bottom)
        ..lineTo(c.rect.right, c.rect.bottom)
        ..close();
      canvas.drawPath(frontPath, Paint()..color = c.column.frontColor);

      final rightPath = Path()
        ..moveTo(c.rect.right, c.rect.top)
        ..lineTo(topRect.right, topRect.top)
        ..lineTo(topRect.right, topRect.bottom)
        ..lineTo(c.rect.right, c.rect.bottom)
        ..close();
      canvas.drawPath(rightPath, Paint()..color = c.column.rightColor);

      canvas.drawRect(topRect, Paint()..color = c.column.topColor);
      canvas.drawRect(
        topRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black.withValues(alpha: 0.18),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ColumnPainter oldDelegate) =>
      columns != oldDelegate.columns || camera != oldDelegate.camera;
}
