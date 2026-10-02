import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';
import '../theme/dark_tile_layer.dart';
import '../theme/ph_icons.dart';
import '../theme/primitives.dart';
import 'crew_models.dart';
import 'crew_navigation_screen.dart';
import 'crew_service.dart';

/// Opens the "who is this, and take me to them" sheet for a crewmate
/// tapped on any map. Shared by the Record map and [CrewMapScreen].
Future<void> showCrewRiderSheet(BuildContext context, CrewLivePosition rider) {
  final ago = DateTime.now().difference(rider.updatedAt);
  final seen = ago.inSeconds < 15 ? 'live now' : 'updated ${ago.inSeconds}s ago';
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Noct.surface,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(rider.displayName,
                style: const TextStyle(fontSize: 18, color: Noct.text, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(
              '${rider.crewNames} · $seen',
              style: const TextStyle(fontSize: 12, color: Noct.n500),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: NoctStat(
                    value: rider.speedKph == null ? '—' : rider.speedKph!.toStringAsFixed(0),
                    suffix: rider.speedKph == null ? null : ' km/h',
                    label: 'Speed',
                  ),
                ),
                Expanded(
                  child: NoctStat(
                    value: rider.leanDeg == null ? '—' : '${rider.leanDeg!.toStringAsFixed(0)}°',
                    label: 'Lean',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Ph.navigationArrow, size: 16, color: Noct.a200),
                label: Text('Navigate to ${rider.displayName}'),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => CrewNavigationScreen(target: rider)));
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Every crewmate riding right now, on one map — reachable from the
/// Crews screen without starting a recording yourself (e.g. "where's
/// everyone?" before heading out to meet them).
class CrewMapScreen extends StatefulWidget {
  const CrewMapScreen({super.key});

  @override
  State<CrewMapScreen> createState() => _CrewMapScreenState();
}

class _CrewMapScreenState extends State<CrewMapScreen> {
  final _mapController = MapController();
  LatLng? _me;
  bool _framed = false;

  @override
  void initState() {
    super.initState();
    CrewService.instance.acquireLiveFeed();
    _loadMe();
  }

  @override
  void dispose() {
    CrewService.instance.releaseLiveFeed();
    super.dispose();
  }

  Future<void> _loadMe() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getLastKnownPosition() ?? await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _me = LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      // No fix — the map just frames the crew instead.
    }
  }

  void _frame(List<CrewLivePosition> riders) {
    if (_framed) return;
    final points = [
      for (final r in riders) LatLng(r.latitude, r.longitude),
      if (_me != null) _me!,
    ];
    if (points.isEmpty) return;
    _framed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (points.length == 1) {
        _mapController.move(points.first, 14);
      } else {
        final bounds = LatLngBounds.fromPoints(points);
        final degenerate = (bounds.north - bounds.south).abs() < 1e-5 && (bounds.east - bounds.west).abs() < 1e-5;
        if (degenerate) {
          _mapController.move(points.first, 15);
        } else {
          _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Crew live', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, letterSpacing: -0.44)),
      ),
      body: ValueListenableBuilder<List<CrewLivePosition>>(
        valueListenable: CrewService.instance.liveCrew,
        builder: (context, riders, _) {
          _frame(riders);
          return Column(
            children: [
              Expanded(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _me ?? const LatLng(0, 0),
                    initialZoom: _me == null ? 2 : 13,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                  ),
                  children: [
                    const DarkTileLayer(),
                    MarkerLayer(
                      markers: [
                        if (_me != null)
                          Marker(
                            point: _me!,
                            width: 14,
                            height: 14,
                            child: const DecoratedBox(
                              decoration: BoxDecoration(color: Noct.a200, shape: BoxShape.circle),
                            ),
                          ),
                        for (final r in riders)
                          Marker(
                            point: LatLng(r.latitude, r.longitude),
                            width: 130,
                            height: 54,
                            child: GestureDetector(
                              onTap: () => showCrewRiderSheet(context, r),
                              child: CrewMarker(name: r.displayName, speedKph: r.speedKph, leanDeg: r.leanDeg),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                color: Noct.bg,
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: riders.isEmpty
                    ? const Text(
                        'Nobody from your crews is riding right now. Crewmates show up here while they record a ride with location sharing on.',
                        style: TextStyle(fontSize: 12.5, color: Noct.n500),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${riders.length} RIDING NOW',
                            style: const TextStyle(fontSize: 10, letterSpacing: 1.2, color: Noct.accent),
                          ),
                          for (final r in riders)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(r.displayName, style: const TextStyle(color: Noct.text, fontSize: 13.5)),
                              subtitle: Text(
                                [
                                  if (r.speedKph != null) '${r.speedKph!.toStringAsFixed(0)} km/h',
                                  if (r.leanDeg != null) '${r.leanDeg!.toStringAsFixed(0)}° lean',
                                  r.crewNames,
                                ].join(' · '),
                                style: const TextStyle(color: Noct.n500, fontSize: 11.5),
                              ),
                              trailing: const Icon(Ph.navigationArrow, size: 16, color: Noct.a300),
                              onTap: () => showCrewRiderSheet(context, r),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
