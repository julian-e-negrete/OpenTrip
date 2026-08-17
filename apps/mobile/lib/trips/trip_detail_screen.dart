import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/models/trip.dart';
import '../data/models/trip_point.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/trip_repository.dart';

class TripDetailScreen extends StatefulWidget {
  const TripDetailScreen({super.key, required this.trip, required this.vehicle});

  final Trip trip;
  final Vehicle? vehicle;

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  List<TripPoint>? _points;

  @override
  void initState() {
    super.initState();
    _loadPoints();
  }

  Future<void> _loadPoints() async {
    // TripRepository.pointsForTrip falls back to a remote pull if this
    // trip has no local points yet (e.g. it arrived via cloud sync from
    // another device) — see sync/sync_service.dart.
    final points = await TripRepository.instance.pointsForTrip(widget.trip.id);
    if (mounted) setState(() => _points = points);
  }

  String _fmtDuration(int seconds) {
    final d = Duration(seconds: seconds);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete trip?'),
        content: Text('This ${widget.trip.distanceKm.toStringAsFixed(2)} km trip will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await TripRepository.instance.deleteTrip(widget.trip.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.vehicle?.name ?? 'Trip'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete trip',
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: ListView(
        children: [
          SizedBox(height: 220, child: _RouteMap(points: _points)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _Row('Started', trip.startedAt.toLocal().toString().substring(0, 19)),
                if (trip.endedAt != null) _Row('Ended', trip.endedAt!.toLocal().toString().substring(0, 19)),
                _Row('Distance', '${trip.distanceKm.toStringAsFixed(2)} km'),
                _Row('Duration', _fmtDuration(trip.durationSeconds)),
                _Row(
                  'Average speed',
                  trip.avgSpeedKph == null ? '—' : '${trip.avgSpeedKph!.toStringAsFixed(1)} km/h',
                ),
                _Row(
                  'Max speed',
                  trip.maxSpeedKph == null ? '—' : '${trip.maxSpeedKph!.toStringAsFixed(1)} km/h',
                ),
                _Row('GPS points recorded', '${trip.pointCount}'),
                if (trip.hasBleTelemetry) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 16, bottom: 4),
                    child: Text(
                      'From the bike',
                      style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (trip.bleMaxSpeedKph != null)
                    _Row('Max speed (bike)', '${trip.bleMaxSpeedKph!.toStringAsFixed(0)} km/h'),
                  if (trip.bleMaxRpm != null) _Row('Max RPM', '${trip.bleMaxRpm}'),
                  if (trip.bleMaxLeanDeg != null)
                    _Row('Max lean angle', '${trip.bleMaxLeanDeg!.toStringAsFixed(0)}°'),
                  if (trip.bleMaxBrakePressureKpa != null)
                    _Row('Max front brake pressure', '${trip.bleMaxBrakePressureKpa!.toStringAsFixed(0)} kPa'),
                  if (trip.bleMinWaterTemperatureC != null && trip.bleMaxWaterTemperatureC != null)
                    _Row(
                      'Water temperature range',
                      '${trip.bleMinWaterTemperatureC}–${trip.bleMaxWaterTemperatureC} °C',
                    ),
                ],
                if (trip.hasBehaviorStats) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 16, bottom: 4),
                    child: Text(
                      'Driving behavior',
                      style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (trip.behaviorMaxAccelG != null)
                    _Row(
                      'Hardest acceleration',
                      '${trip.behaviorMaxAccelG!.toStringAsFixed(2)}g'
                      '${trip.behaviorHardAccelCount == null ? '' : ' · ${trip.behaviorHardAccelCount} hard'}',
                    ),
                  if (trip.behaviorMaxBrakeG != null)
                    _Row(
                      'Hardest braking',
                      '${trip.behaviorMaxBrakeG!.toStringAsFixed(2)}g'
                      '${trip.behaviorHardBrakeCount == null ? '' : ' · ${trip.behaviorHardBrakeCount} hard'}',
                    ),
                  if (trip.behaviorMaxCorneringG != null)
                    _Row(
                      'Hardest cornering',
                      '${trip.behaviorMaxCorneringG!.toStringAsFixed(2)}g'
                      '${trip.behaviorHardCorneringCount == null ? '' : ' · ${trip.behaviorHardCorneringCount} hard'}',
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

/// Route polyline over OpenStreetMap raster tiles. Uses the public
/// tile.openstreetmap.org server, which is fine for this app's current
/// scale but comes with OSM's tile usage policy (low volume, no heavy
/// production traffic) — see docs/ROADMAP.md. Self-hosting tiles or
/// switching to a paid provider (Stadia Maps, MapTiler, Thunderforest)
/// is the documented upgrade path if that ever becomes a real concern.
class _RouteMap extends StatelessWidget {
  const _RouteMap({required this.points});
  final List<TripPoint>? points;

  @override
  Widget build(BuildContext context) {
    final pts = points;
    if (pts == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (pts.isEmpty) {
      return const ColoredBox(
        color: Color(0xFF1A1A1A),
        child: Center(child: Text('No route recorded for this trip.')),
      );
    }

    final routePoints = pts.map((p) => LatLng(p.latitude, p.longitude)).toList();
    final bounds = LatLngBounds.fromPoints(routePoints);

    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(32)),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'co.opentrip.opentrip_mobile',
        ),
        PolylineLayer(
          polylines: [Polyline(points: routePoints, strokeWidth: 4, color: Colors.tealAccent)],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: routePoints.first,
              width: 16,
              height: 16,
              child: const DecoratedBox(
                decoration: BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
              ),
            ),
            Marker(
              point: routePoints.last,
              width: 16,
              height: 16,
              child: const DecoratedBox(
                decoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
