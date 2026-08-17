import 'package:flutter/material.dart';

import '../auth/current_user.dart';
import '../data/data_events.dart';
import '../data/models/trip.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/trip_repository.dart';
import '../data/repositories/vehicle_repository.dart';
import '../leaderboard/leaderboard_screen.dart';
import 'trip_detail_screen.dart';

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  List<Trip> _trips = [];
  Map<String, Vehicle> _vehiclesById = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // This screen lives inside HomeShell's IndexedStack, so initState only
    // ever runs once — reload whenever a trip is started/finished/deleted
    // elsewhere. See data/data_events.dart.
    DataEvents.instance.listenable.addListener(_load);
  }

  @override
  void dispose() {
    DataEvents.instance.listenable.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final userId = await CurrentUser.instance.id();
    final trips = await TripRepository.instance.listForUser(userId);
    final vehicles = await VehicleRepository.instance.listForUser(userId);
    if (!mounted) return;
    setState(() {
      _trips = trips;
      _vehiclesById = {for (final v in vehicles) v.id: v};
      _loading = false;
    });
  }

  String _fmtDuration(int seconds) {
    final d = Duration(seconds: seconds);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  Future<bool> _confirmDelete(Trip trip) async {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trips'),
        actions: [
          IconButton(
            icon: const Icon(Icons.leaderboard_outlined),
            tooltip: 'Leaderboard',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _trips.isEmpty
          ? const Center(child: Text('No trips recorded yet.'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                itemCount: _trips.length,
                itemBuilder: (context, i) {
                  final trip = _trips[i];
                  final vehicle = _vehiclesById[trip.vehicleId];
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
                    confirmDismiss: (_) => _confirmDelete(trip),
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
                          '${vehicle?.name ?? 'Unknown vehicle'} · '
                          '${trip.startedAt.toLocal().toString().substring(0, 16)} · '
                          '${_fmtDuration(trip.durationSeconds)}',
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
                },
              ),
            ),
    );
  }
}
