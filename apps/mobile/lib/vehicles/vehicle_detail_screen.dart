import 'package:flutter/material.dart';

import '../data/data_events.dart';
import '../data/models/trip.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/trip_repository.dart';
import '../data/repositories/vehicle_repository.dart';
import '../theme/app_theme.dart';
import '../theme/date_fmt.dart';
import '../theme/num_fmt.dart';
import '../theme/ph_icons.dart';
import '../theme/primitives.dart';
import '../trips/trip_detail_screen.dart';
import 'add_vehicle_screen.dart';

/// A vehicle's own profile — its photo/name/type up top, lifetime stats
/// folded from every trip ever recorded on it (client-side, same pattern
/// account_screen.dart and gamification/monthly_recap_screen.dart already
/// use), and the full list of its trips below, each tapping into the
/// same trips/trip_detail_screen.dart the Trips tab uses.
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
      if (refreshed != null) _vehicle = refreshed;
      _loading = false;
    });
  }

  Future<void> _edit() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddVehicleScreen(vehicle: _vehicle)));
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete vehicle?'),
        content: Text('"${_vehicle.name}" and its trips will be removed from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(dialogContext).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await VehicleRepository.instance.delete(_vehicle.id);
    if (mounted) Navigator.of(context).pop();
  }

  ({double km, bool fromBike}) _currentMileage() {
    for (final t in _trips) {
      if (t.bleOdometerKm != null) return (km: t.bleOdometerKm!, fromBike: true);
    }
    final totalDistanceKm = _trips.fold<double>(0, (sum, t) => sum + t.distanceMeters) / 1000.0;
    return (km: (_vehicle.startingOdometerKm ?? 0) + totalDistanceKm, fromBike: false);
  }

  Future<void> _logService() async {
    final mileage = _currentMileage();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log a service?'),
        content: Text(
          'Marks ${mileage.km.toStringAsFixed(0)} km as this vehicle\'s last service — '
          'the next one is due ${_vehicle.serviceIntervalKm?.toStringAsFixed(0)} km after that.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Log it')),
        ],
      ),
    );
    if (confirmed != true) return;
    await VehicleRepository.instance.update(_vehicle.copyWith(lastServiceOdometerKm: mileage.km, synced: false));
  }

  Future<bool> _confirmDeleteTrip(Trip trip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete trip?'),
        content: Text('This ${trip.distanceKm.toStringAsFixed(2)} km trip will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(dialogContext).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  String _fmtDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours == 0) return '${minutes}m';
    return '${hours}h ${minutes}m';
  }

  String _typeLabel(VehicleType type) => switch (type) {
    VehicleType.motorcycle => 'Motorcycle',
    VehicleType.car => 'Car',
    VehicleType.bicycle => 'Bicycle',
    VehicleType.other => 'Vehicle',
  };

  @override
  Widget build(BuildContext context) {
    final supportsBle = _vehicle.bleConnector == VehicleBleConnector.kawasakiRideology;
    final kicker = supportsBle ? '${_typeLabel(_vehicle.type)} · Kawasaki Rideology BLE' : _typeLabel(_vehicle.type);

    return Scaffold(
      appBar: AppBar(
        title: const SizedBox.shrink(),
        actions: [
          IconButton(icon: const Icon(Ph.pencilSimple, size: 18, color: Noct.n400), tooltip: 'Edit', onPressed: _edit),
          IconButton(icon: const Icon(Ph.trash, size: 18, color: Noct.n400), tooltip: 'Delete', onPressed: _delete),
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
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          kicker.toUpperCase(),
                          style: const TextStyle(fontSize: 10, letterSpacing: 1.2, color: Noct.n500, fontWeight: FontWeight.w400),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _vehicle.name,
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500, letterSpacing: -0.7, color: Noct.text),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
                    child: _OdometerPanel(vehicle: _vehicle, mileage: _currentMileage(), onLogService: _logService),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                    child: _ThreeStatGrid(trips: _trips, fmtDuration: _fmtDuration),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 22, 18, 0),
                    child: _BikeRecords(trips: _trips),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 22, 18, 8),
                    child: _RecentTrips(trips: _trips, vehicle: _vehicle, onConfirmDelete: _confirmDeleteTrip),
                  ),
                ],
              ),
            ),
    );
  }
}

class _OdometerPanel extends StatelessWidget {
  const _OdometerPanel({required this.vehicle, required this.mileage, required this.onLogService});
  final Vehicle vehicle;
  final ({double km, bool fromBike}) mileage;
  final VoidCallback onLogService;

  @override
  Widget build(BuildContext context) {
    final serviceInterval = vehicle.serviceIntervalKm;
    double? remainingKm;
    double? progress;
    var overdue = false;
    if (serviceInterval != null && serviceInterval > 0) {
      final baseline = vehicle.lastServiceOdometerKm ?? (vehicle.startingOdometerKm ?? 0);
      remainingKm = baseline + serviceInterval - mileage.km;
      overdue = remainingKm < 0;
      progress = ((mileage.km - baseline) / serviceInterval).clamp(0.0, 1.0);
    }

    return NoctPanel(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: fmtThousands(mileage.km.round()), style: Noct.stat(34)),
                TextSpan(
                  text: mileage.fromBike ? " km · from the bike's odometer" : ' km · estimated from recorded trips',
                  style: const TextStyle(fontSize: 12, color: Noct.n400, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),
          if (serviceInterval != null) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  overdue ? 'Service overdue' : 'Next service in',
                  style: const TextStyle(fontSize: 11.5, color: Noct.n400, fontWeight: FontWeight.w400),
                ),
                Text(
                  overdue ? '${fmtThousands((-remainingKm!).round())} km ago' : '${fmtThousands(remainingKm!.round())} km',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: overdue ? Theme.of(context).colorScheme.error : Noct.a300,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: ColoredBox(
                  color: Noct.n900,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress ?? 0,
                    child: ColoredBox(color: overdue ? Theme.of(context).colorScheme.error : Noct.accent),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: onLogService,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                  side: const BorderSide(color: Noct.accent, width: 1),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('Log service now'),
              ),
            ),
          ] else
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onLogService, child: const Text('Set a service interval')),
            ),
        ],
      ),
    );
  }
}

class _ThreeStatGrid extends StatelessWidget {
  const _ThreeStatGrid({required this.trips, required this.fmtDuration});
  final List<Trip> trips;
  final String Function(int) fmtDuration;

  @override
  Widget build(BuildContext context) {
    final totalDistanceMeters = trips.fold<double>(0, (sum, t) => sum + t.distanceMeters);
    final totalDurationSeconds = trips.fold<int>(0, (sum, t) => sum + t.durationSeconds);
    return Row(
      children: [
        Expanded(child: NoctPanel(padding: const EdgeInsets.all(12), child: NoctStat(value: '${trips.length}', label: 'Trips', valueSize: 19))),
        const SizedBox(width: 9),
        Expanded(
          child: NoctPanel(
            padding: const EdgeInsets.all(12),
            child: NoctStat(value: fmtThousands((totalDistanceMeters / 1000).round()), suffix: ' km', label: 'Total', valueSize: 19),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: NoctPanel(padding: const EdgeInsets.all(12), child: NoctStat(value: fmtDuration(totalDurationSeconds), label: 'Riding', valueSize: 19)),
        ),
      ],
    );
  }
}

class _BikeRecords extends StatelessWidget {
  const _BikeRecords({required this.trips});
  final List<Trip> trips;

  @override
  Widget build(BuildContext context) {
    double? maxBleSpeed;
    double? maxLean;
    double longestMeters = 0;
    for (final t in trips) {
      if (t.bleMaxSpeedKph != null && (maxBleSpeed == null || t.bleMaxSpeedKph! > maxBleSpeed)) {
        maxBleSpeed = t.bleMaxSpeedKph;
      }
      final leanDeg = t.bleMaxLeanDeg ?? t.phoneLeanMaxDeg;
      if (leanDeg != null && (maxLean == null || leanDeg > maxLean)) maxLean = leanDeg;
      if (t.distanceMeters > longestMeters) longestMeters = t.distanceMeters;
    }

    final rows = [
      if (maxBleSpeed != null) ('Fastest recorded', '${maxBleSpeed.toStringAsFixed(0)} km/h'),
      if (maxLean != null) ('Deepest lean', '${maxLean.toStringAsFixed(0)}°'),
      if (longestMeters > 0) ('Longest trip', '${(longestMeters / 1000).toStringAsFixed(0)} km'),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'BIKE RECORDS',
          style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: Noct.accent, fontWeight: FontWeight.w400),
        ),
        const SizedBox(height: 8),
        for (final (label, value) in rows)
          Container(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Noct.n900, width: 1))),
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontSize: 13, color: Noct.n400, fontWeight: FontWeight.w400)),
                Text(value, style: const TextStyle(fontSize: 13, color: Noct.text, fontWeight: FontWeight.w400)),
              ],
            ),
          ),
      ],
    );
  }
}

class _RecentTrips extends StatelessWidget {
  const _RecentTrips({required this.trips, required this.vehicle, required this.onConfirmDelete});
  final List<Trip> trips;
  final Vehicle vehicle;
  final Future<bool> Function(Trip) onConfirmDelete;

  String _fmtDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'RECENT TRIPS',
          style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: Noct.n500, fontWeight: FontWeight.w400),
        ),
        const SizedBox(height: 8),
        if (trips.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No trips recorded with this vehicle yet.', style: TextStyle(color: Noct.n500, fontSize: 13)),
          )
        else
          for (final trip in trips)
            Dismissible(
              key: ValueKey(trip.id),
              direction: DismissDirection.endToStart,
              background: Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.error, borderRadius: BorderRadius.circular(Noct.rMd)),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Icon(Ph.trash, color: Theme.of(context).colorScheme.onError, size: 16),
              ),
              confirmDismiss: (_) => onConfirmDelete(trip),
              onDismissed: (_) => TripRepository.instance.deleteTrip(trip.id),
              child: InkWell(
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => TripDetailScreen(trip: trip, vehicle: vehicle))),
                overlayColor: WidgetStatePropertyAll(Noct.accent.withValues(alpha: 0.05)),
                child: Container(
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Noct.n900, width: 1))),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${trip.distanceKm.toStringAsFixed(1)} km',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Noct.text,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            Text(
                              '${fmtDayMonth(trip.startedAt)} · ${_fmtDuration(trip.durationSeconds)}',
                              style: const TextStyle(fontSize: 11, color: Noct.n500),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Ph.caretRight, size: 13, color: Noct.n600),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
