import 'dart:io';

import 'package:flutter/material.dart';

import '../data/data_events.dart';
import '../data/models/trip.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/trip_repository.dart';
import '../data/repositories/vehicle_repository.dart';
import '../trips/trip_detail_screen.dart';
import 'add_vehicle_screen.dart';

/// A vehicle's own profile — its photo/name/type up top, lifetime stats
/// folded from every trip ever recorded on it (client-side, same pattern
/// account_screen.dart and gamification/monthly_recap_screen.dart already
/// use — cheap at this app's scale, no new aggregate query needed), and
/// the full list of its trips below, each tapping into the same
/// trips/trip_detail_screen.dart the Trips tab uses. Reached by tapping a
/// vehicle on vehicles/vehicle_list_screen.dart; edit/delete live here
/// now instead of on the list row, the same way a profile page — not a
/// list item — is where you'd expect to manage one specific thing.
class VehicleDetailScreen extends StatefulWidget {
  const VehicleDetailScreen({super.key, required this.vehicle});

  final Vehicle vehicle;

  @override
  State<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends State<VehicleDetailScreen> {
  late Vehicle _vehicle;
  List<Trip> _trips = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _vehicle = widget.vehicle;
    _load();
    // Unlike the tabs inside HomeShell's IndexedStack, this screen is
    // pushed fresh each time (see vehicle_list_screen.dart), so it
    // wouldn't strictly need a listener to catch its *own* first load —
    // but it does need one to catch a trip finishing on this vehicle
    // while this detail screen is still on screen (e.g. after backing
    // out of a just-finished recording), and to pick up this vehicle's
    // own edits reflected back from add_vehicle_screen.dart. See
    // data/data_events.dart.
    DataEvents.instance.listenable.addListener(_load);
  }

  @override
  void dispose() {
    DataEvents.instance.listenable.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final trips = await TripRepository.instance.listForVehicle(_vehicle.id);
    final vehicles = await VehicleRepository.instance.listForUser(_vehicle.userId);
    if (!mounted) return;
    Vehicle? refreshed;
    for (final v in vehicles) {
      if (v.id == _vehicle.id) {
        refreshed = v;
        break;
      }
    }
    setState(() {
      _trips = trips;
      // refreshed comes back null if this vehicle was just deleted (from
      // this same screen's own delete button, which pops immediately
      // after) — keep showing the last-known vehicle rather than crash
      // on a still-in-flight frame.
      if (refreshed != null) _vehicle = refreshed;
      _loading = false;
    });
  }

  Future<void> _edit() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddVehicleScreen(vehicle: _vehicle)));
    // No manual _load() needed — VehicleRepository.update fires
    // DataEvents, which this screen already listens to.
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete vehicle?'),
        content: Text('"${_vehicle.name}" and its trips will be removed from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await VehicleRepository.instance.delete(_vehicle.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<bool> _confirmDeleteTrip(Trip trip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete trip?'),
        content: Text('This ${trip.distanceKm.toStringAsFixed(2)} km trip will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  IconData _iconFor(VehicleType type) => switch (type) {
    VehicleType.motorcycle => Icons.two_wheeler,
    VehicleType.car => Icons.directions_car,
    VehicleType.bicycle => Icons.pedal_bike,
    VehicleType.other => Icons.directions,
  };

  String _fmtDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours == 0) return '${minutes}m';
    return '${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_vehicle.name),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit', onPressed: _edit),
          IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete', onPressed: _delete),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _Header(vehicle: _vehicle, iconFor: _iconFor),
                  const SizedBox(height: 24),
                  _buildStatsGrid(scheme),
                  ..._buildBikeRecords(scheme),
                  const SizedBox(height: 24),
                  Text(
                    'Trips',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: scheme.onSurface),
                  ),
                  const SizedBox(height: 8),
                  if (_trips.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'No trips recorded with this vehicle yet.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  else
                    ..._trips.map(
                      (trip) => _TripRow(trip: trip, vehicle: _vehicle, onConfirmDelete: _confirmDeleteTrip),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatsGrid(ColorScheme scheme) {
    final totalDistanceMeters = _trips.fold<double>(0, (sum, t) => sum + t.distanceMeters);
    final totalDurationSeconds = _trips.fold<int>(0, (sum, t) => sum + t.durationSeconds);
    final longestMeters = _trips.fold<double>(0, (max, t) => t.distanceMeters > max ? t.distanceMeters : max);
    double? topSpeedKph;
    for (final t in _trips) {
      if (t.maxSpeedKph != null && (topSpeedKph == null || t.maxSpeedKph! > topSpeedKph)) {
        topSpeedKph = t.maxSpeedKph;
      }
    }
    final avgSpeedKph = totalDurationSeconds > 0 ? totalDistanceMeters / totalDurationSeconds * 3.6 : null;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.7,
      children: [
        _StatCard('Trips', '${_trips.length}', scheme.onSurface),
        _StatCard('Distance', '${(totalDistanceMeters / 1000).toStringAsFixed(0)} km', scheme.secondary),
        _StatCard('Time riding', _fmtDuration(totalDurationSeconds), scheme.onSurface),
        _StatCard('Longest trip', '${(longestMeters / 1000).toStringAsFixed(0)} km', scheme.secondary),
        _StatCard('Avg speed', avgSpeedKph == null ? '—' : '${avgSpeedKph.toStringAsFixed(0)} km/h', scheme.primary),
        _StatCard('Top speed', topSpeedKph == null ? '—' : '${topSpeedKph.toStringAsFixed(0)} km/h', scheme.primary),
      ],
    );
  }

  /// A second, optional row of stats — only shown once this vehicle has
  /// actually reported BLE telemetry on at least one trip (see
  /// data/models/trip.dart's [Trip.hasBleTelemetry]), same gating
  /// trips/trip_detail_screen.dart uses for its own "From the bike"
  /// section on a single trip. Here it's folded across every trip
  /// instead of just one.
  List<Widget> _buildBikeRecords(ColorScheme scheme) {
    double? maxBleSpeed;
    double? maxBleLean;
    for (final t in _trips) {
      if (t.bleMaxSpeedKph != null && (maxBleSpeed == null || t.bleMaxSpeedKph! > maxBleSpeed)) {
        maxBleSpeed = t.bleMaxSpeedKph;
      }
      if (t.bleMaxLeanDeg != null && (maxBleLean == null || t.bleMaxLeanDeg! > maxBleLean)) {
        maxBleLean = t.bleMaxLeanDeg;
      }
    }
    if (maxBleSpeed == null && maxBleLean == null) return const [];

    return [
      const SizedBox(height: 20),
      Text(
        'Bike records',
        style: TextStyle(color: scheme.tertiary, fontWeight: FontWeight.w800, letterSpacing: 0.3),
      ),
      if (maxBleSpeed != null) _KeyValueRow('Fastest recorded (bike)', '${maxBleSpeed.toStringAsFixed(0)} km/h'),
      if (maxBleLean != null) _KeyValueRow('Deepest lean (bike)', '${maxBleLean.toStringAsFixed(0)}°'),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.vehicle, required this.iconFor});
  final Vehicle vehicle;
  final IconData Function(VehicleType) iconFor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        CircleAvatar(
          radius: 44,
          backgroundColor: scheme.primary.withValues(alpha: 0.16),
          backgroundImage: vehicle.photoPath != null ? FileImage(File(vehicle.photoPath!)) : null,
          child: vehicle.photoPath == null ? Icon(iconFor(vehicle.type), size: 36, color: scheme.primary) : null,
        ),
        const SizedBox(height: 12),
        Text(vehicle.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
        const SizedBox(height: 4),
        Text(
          vehicle.bleConnector == VehicleBleConnector.none
              ? vehicle.type.name
              : '${vehicle.type.name} · Kawasaki Rideology BLE',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.label, this.value, this.valueColor);
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: valueColor)),
            Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _TripRow extends StatelessWidget {
  const _TripRow({required this.trip, required this.vehicle, required this.onConfirmDelete});
  final Trip trip;
  final Vehicle vehicle;
  final Future<bool> Function(Trip) onConfirmDelete;

  String _fmtDuration(int seconds) {
    final d = Duration(seconds: seconds);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey(trip.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: scheme.error, borderRadius: BorderRadius.circular(18)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Icon(Icons.delete_outline, color: scheme.onError),
      ),
      confirmDismiss: (_) => onConfirmDelete(trip),
      onDismissed: (_) => TripRepository.instance.deleteTrip(trip.id),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: scheme.secondary.withValues(alpha: 0.16),
            child: Icon(Icons.route_outlined, color: scheme.secondary),
          ),
          title: Text(
            '${trip.distanceKm.toStringAsFixed(2)} km',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          subtitle: Text(
            '${trip.startedAt.toLocal().toString().substring(0, 16)} · ${_fmtDuration(trip.durationSeconds)}',
          ),
          trailing: trip.isFinished
              ? null
              : Chip(
                  label: const Text('In progress'),
                  backgroundColor: scheme.primary.withValues(alpha: 0.16),
                  labelStyle: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
                  side: BorderSide.none,
                ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TripDetailScreen(trip: trip, vehicle: vehicle)),
          ),
        ),
      ),
    );
  }
}
