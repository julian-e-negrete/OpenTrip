import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/current_user.dart';
import '../data/data_events.dart';
import '../data/models/trip.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/trip_repository.dart';
import '../data/repositories/vehicle_repository.dart';
import '../theme/app_theme.dart';
import '../theme/ph_icons.dart';
import '../theme/primitives.dart';
import 'solo_race_screen.dart';

/// Racing tab root: pick a vehicle, see personal bests so far for it, and
/// start a solo roll race (racing/solo_race_screen.dart) — one
/// continuous run measuring both 0-60 km/h (an in-run checkpoint) and
/// 0-180 km/h (the finish line) from the same standing start. "Race a
/// friend" is a visible, clearly labeled placeholder — the live
/// two-phone linked race (a Supabase Realtime room with a synchronized
/// countdown) is a separate follow-up phase, not built yet, so this
/// doesn't pretend to work.
class RacingScreen extends StatefulWidget {
  const RacingScreen({super.key});

  @override
  State<RacingScreen> createState() => _RacingScreenState();
}

class _RacingScreenState extends State<RacingScreen> {
  List<Vehicle> _vehicles = [];
  Vehicle? _selectedVehicle;
  List<Trip> _vehicleTrips = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    DataEvents.instance.listenable.addListener(_load);
  }

  @override
  void dispose() {
    DataEvents.instance.listenable.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final userId = await CurrentUser.instance.id();
    final vehicles = await VehicleRepository.instance.listForUser(userId);
    if (!mounted) return;
    final selected = _selectedVehicle;
    final stillExists = selected != null && vehicles.any((v) => v.id == selected.id);
    final vehicle = stillExists ? selected : (vehicles.isEmpty ? null : vehicles.first);
    setState(() {
      _vehicles = vehicles;
      _selectedVehicle = vehicle;
      _loading = false;
    });
    if (vehicle != null) await _loadTripsFor(vehicle);
  }

  Future<void> _loadTripsFor(Vehicle vehicle) async {
    final trips = await TripRepository.instance.listForVehicle(vehicle.id);
    if (!mounted) return;
    setState(() => _vehicleTrips = trips);
  }

  double? _bestOf(double? Function(Trip) selector) {
    final values = _vehicleTrips.map(selector).whereType<double>();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a < b ? a : b);
  }

  Future<void> _start() async {
    final vehicle = _selectedVehicle;
    if (vehicle == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SoloRaceScreen(vehicle: vehicle)));
    await _load();
  }

  void _raceAFriend() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Racing a friend is coming soon — solo runs work today.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bestZeroToSixty = _bestOf((t) => t.best0To60Seconds);
    final bestZeroToOneEighty = _bestOf((t) => t.best0To180Seconds);
    return Scaffold(
      appBar: AppBar(title: const Text('Racing')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _vehicles.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Add a vehicle in Garage first to start racing.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Noct.n500),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    const Text('VEHICLE', style: Noct.statLabel),
                    const SizedBox(height: 9),
                    NoctSegmentedControl<Vehicle>(
                      options: [for (final v in _vehicles) (v, v.name)],
                      value: _selectedVehicle!,
                      onChanged: (v) {
                        setState(() => _selectedVehicle = v);
                        unawaited(_loadTripsFor(v));
                      },
                    ),
                    const SizedBox(height: 22),
                    const Text('PERSONAL BEST', style: Noct.statLabel),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Expanded(
                          child: NoctPanel(
                            child: NoctStat(
                              value: bestZeroToSixty == null ? '—' : bestZeroToSixty.toStringAsFixed(2),
                              suffix: bestZeroToSixty == null ? null : 's',
                              label: '0-60 km/h',
                              valueSize: 28,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: NoctPanel(
                            child: NoctStat(
                              value: bestZeroToOneEighty == null ? '—' : bestZeroToOneEighty.toStringAsFixed(2),
                              suffix: bestZeroToOneEighty == null ? null : 's',
                              label: '0-180 km/h',
                              valueSize: 28,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    NoctOutlinedButton(label: 'Start roll race', icon: Ph.flagCheckered, onPressed: _start),
                    const SizedBox(height: 10),
                    NoctOutlinedButton(label: 'Race a friend (coming soon)', onPressed: _raceAFriend),
                  ],
                ),
    );
  }
}
