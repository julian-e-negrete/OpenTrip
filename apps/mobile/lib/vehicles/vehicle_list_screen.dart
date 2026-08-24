import 'dart:io';

import 'package:flutter/material.dart';

import '../auth/current_user.dart';
import '../data/data_events.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/vehicle_repository.dart';
import 'add_vehicle_screen.dart';

class VehicleListScreen extends StatefulWidget {
  const VehicleListScreen({super.key});

  @override
  State<VehicleListScreen> createState() => _VehicleListScreenState();
}

class _VehicleListScreenState extends State<VehicleListScreen> {
  List<Vehicle> _vehicles = [];
  bool _loading = true;
  late String _userId;

  @override
  void initState() {
    super.initState();
    _load();
    // This screen lives inside HomeShell's IndexedStack, so initState only
    // ever runs once — reload whenever any repository reports a change,
    // not just after this screen's own actions. See data/data_events.dart.
    DataEvents.instance.listenable.addListener(_load);
  }

  @override
  void dispose() {
    DataEvents.instance.listenable.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    _userId = await CurrentUser.instance.id();
    final vehicles = await VehicleRepository.instance.listForUser(_userId);
    if (!mounted) return;
    setState(() {
      _vehicles = vehicles;
      _loading = false;
    });
  }

  Future<void> _addVehicle() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddVehicleScreen()));
    // No manual _load() needed here — VehicleRepository.create fires
    // DataEvents, which this screen already listens to.
  }

  Future<void> _deleteVehicle(Vehicle vehicle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete vehicle?'),
        content: Text('"${vehicle.name}" and its trips will be removed from this device.'),
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
    await VehicleRepository.instance.delete(vehicle.id);
  }

  IconData _iconFor(VehicleType type) => switch (type) {
    VehicleType.motorcycle => Icons.two_wheeler,
    VehicleType.car => Icons.directions_car,
    VehicleType.bicycle => Icons.pedal_bike,
    VehicleType.other => Icons.directions,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicles'),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _addVehicle)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _vehicles.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No vehicles yet.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _addVehicle,
                    icon: const Icon(Icons.add),
                    label: const Text('Add a vehicle'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              itemCount: _vehicles.length,
              itemBuilder: (context, i) {
                final vehicle = _vehicles[i];
                final scheme = Theme.of(context).colorScheme;
                return Card(
                  child: ListTile(
                    leading: vehicle.photoPath != null
                        ? CircleAvatar(backgroundImage: FileImage(File(vehicle.photoPath!)))
                        : CircleAvatar(
                            backgroundColor: scheme.primary.withValues(alpha: 0.16),
                            child: Icon(_iconFor(vehicle.type), color: scheme.primary),
                          ),
                    title: Text(vehicle.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                      vehicle.bleConnector == VehicleBleConnector.none
                          ? vehicle.type.name
                          : '${vehicle.type.name} · Kawasaki Rideology BLE',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteVehicle(vehicle),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
