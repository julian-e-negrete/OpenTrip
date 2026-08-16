import 'package:flutter/material.dart';

import '../auth/current_user.dart';
import '../data/data_events.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/vehicle_repository.dart';

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
    final result = await showDialog<({String name, VehicleType type, VehicleBleConnector connector})>(
      context: context,
      builder: (_) => const _AddVehicleDialog(),
    );
    if (result == null) return;

    await VehicleRepository.instance.create(
      userId: _userId,
      name: result.name,
      type: result.type,
      bleConnector: result.connector,
    );
    await _load();
  }

  Future<void> _deleteVehicle(Vehicle vehicle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete vehicle?'),
        content: Text('"${vehicle.name}" and its trips will be removed from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await VehicleRepository.instance.delete(vehicle.id);
    await _load();
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
              itemCount: _vehicles.length,
              itemBuilder: (context, i) {
                final vehicle = _vehicles[i];
                return ListTile(
                  leading: Icon(_iconFor(vehicle.type)),
                  title: Text(vehicle.name),
                  subtitle: Text(
                    vehicle.bleConnector == VehicleBleConnector.none
                        ? vehicle.type.name
                        : '${vehicle.type.name} · Kawasaki Rideology BLE',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteVehicle(vehicle),
                  ),
                );
              },
            ),
    );
  }
}

class _AddVehicleDialog extends StatefulWidget {
  const _AddVehicleDialog();

  @override
  State<_AddVehicleDialog> createState() => _AddVehicleDialogState();
}

class _AddVehicleDialogState extends State<_AddVehicleDialog> {
  final _nameController = TextEditingController();
  VehicleType _type = VehicleType.motorcycle;
  bool _kawasakiBle = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add vehicle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name (e.g. "My Z500")'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<VehicleType>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: VehicleType.values
                .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                .toList(),
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          if (_type == VehicleType.motorcycle) ...[
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Kawasaki Rideology BLE (Z500/Z500 ABS/Ninja 500)'),
              value: _kawasakiBle,
              onChanged: (v) => setState(() => _kawasakiBle = v ?? false),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, (
              name: name,
              type: _type,
              connector: _kawasakiBle ? VehicleBleConnector.kawasakiRideology : VehicleBleConnector.none,
            ));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
