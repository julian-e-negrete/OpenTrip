import 'package:flutter/material.dart';

import '../data/models/trip.dart';
import '../data/models/vehicle.dart';

/// Trip stats only — no map rendering yet. Route points are already being
/// recorded and persisted (see data/repositories/trip_repository.dart's
/// pointsForTrip), so a map view is a UI-only follow-up once MapLibre is
/// wired in (/docs/ROADMAP.md).
class TripDetailScreen extends StatelessWidget {
  const TripDetailScreen({super.key, required this.trip, required this.vehicle});

  final Trip trip;
  final Vehicle? vehicle;

  String _fmtDuration(int seconds) {
    final d = Duration(seconds: seconds);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(vehicle?.name ?? 'Trip')),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
              child: Text('From the bike', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            if (trip.bleMaxSpeedKph != null)
              _Row('Max speed (bike)', '${trip.bleMaxSpeedKph!.toStringAsFixed(0)} km/h'),
            if (trip.bleMaxRpm != null) _Row('Max RPM', '${trip.bleMaxRpm}'),
            if (trip.bleMaxLeanDeg != null) _Row('Max lean angle', '${trip.bleMaxLeanDeg!.toStringAsFixed(0)}°'),
            if (trip.bleMaxBrakePressureKpa != null)
              _Row('Max front brake pressure', '${trip.bleMaxBrakePressureKpa!.toStringAsFixed(0)} kPa'),
            if (trip.bleMinWaterTemperatureC != null && trip.bleMaxWaterTemperatureC != null)
              _Row(
                'Water temperature range',
                '${trip.bleMinWaterTemperatureC}–${trip.bleMaxWaterTemperatureC} °C',
              ),
          ],
        ],
      ),
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
