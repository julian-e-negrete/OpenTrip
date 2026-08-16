import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../data/models/trip.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/trip_repository.dart';
import '../data/repositories/vehicle_repository.dart';
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

  String get _userId => AuthService.instance.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final trips = await TripRepository.instance.listForUser(_userId);
    final vehicles = await VehicleRepository.instance.listForUser(_userId);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trips')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _trips.isEmpty
          ? const Center(child: Text('No trips recorded yet.'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                itemCount: _trips.length,
                itemBuilder: (context, i) {
                  final trip = _trips[i];
                  final vehicle = _vehiclesById[trip.vehicleId];
                  return ListTile(
                    leading: const Icon(Icons.route_outlined),
                    title: Text('${trip.distanceKm.toStringAsFixed(2)} km'),
                    subtitle: Text(
                      '${vehicle?.name ?? 'Unknown vehicle'} · '
                      '${trip.startedAt.toLocal().toString().substring(0, 16)} · '
                      '${_fmtDuration(trip.durationSeconds)}',
                    ),
                    trailing: trip.isFinished ? null : const Chip(label: Text('In progress')),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => TripDetailScreen(trip: trip, vehicle: vehicle)),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
