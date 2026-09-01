import 'dart:io';

import 'package:flutter/material.dart';

import '../account/account_screen.dart';
import '../auth/current_user.dart';
import '../data/data_events.dart';
import '../data/models/trip.dart';
import '../data/models/vehicle.dart';
import '../data/repositories/trip_repository.dart';
import '../data/repositories/vehicle_repository.dart';
import '../theme/app_theme.dart';
import '../theme/ph_icons.dart';
import '../theme/primitives.dart';
import '../vehicle/ble_connection_service.dart';
import 'add_vehicle_screen.dart';
import 'vehicle_detail_screen.dart';

class VehicleListScreen extends StatefulWidget {
  const VehicleListScreen({super.key});

  @override
  State<VehicleListScreen> createState() => _VehicleListScreenState();
}

class _VehicleListScreenState extends State<VehicleListScreen> {
  List<Vehicle> _vehicles = [];
  Map<String, List<Trip>> _tripsByVehicle = {};
  bool _loading = true;
  late String _userId;

  final _ble = BleConnectionService.instance;
  String? _connectingVehicleId;

  @override
  void initState() {
    super.initState();
    _load();
    // This screen lives inside HomeShell's Garage tab navigator, mounted
    // for the app's lifetime — reload whenever any repository reports a
    // change. See data/data_events.dart.
    DataEvents.instance.listenable.addListener(_load);
    _ble.stateNotifier.addListener(_onBleStateChanged);
  }

  @override
  void dispose() {
    DataEvents.instance.listenable.removeListener(_load);
    _ble.stateNotifier.removeListener(_onBleStateChanged);
    super.dispose();
  }

  void _onBleStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    _userId = await CurrentUser.instance.id();
    final vehicles = await VehicleRepository.instance.listForUser(_userId);
    // Cheap at this app's scale (a handful of vehicles) — same pattern
    // vehicle_detail_screen.dart and account_screen.dart already use for
    // their own client-side stat folds, just spread across every vehicle
    // instead of one.
    final tripsByVehicle = <String, List<Trip>>{};
    for (final v in vehicles) {
      tripsByVehicle[v.id] = await TripRepository.instance.listForVehicle(v.id);
    }
    if (!mounted) return;
    setState(() {
      _vehicles = vehicles;
      _tripsByVehicle = tripsByVehicle;
      _loading = false;
    });
  }

  Future<void> _addVehicle() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddVehicleScreen()));
    // No manual _load() needed here — VehicleRepository.create fires
    // DataEvents, which this screen already listens to.
  }

  Future<void> _toggleConnection(Vehicle vehicle) async {
    if (_ble.isConnected && _connectingVehicleId == vehicle.id) {
      await _ble.disconnect();
      _connectingVehicleId = null;
      return;
    }
    if (_ble.isBusy) return;
    _connectingVehicleId = vehicle.id;
    await _ble.connect();
  }

  /// This vehicle's current mileage — prefers the most recent trip's BLE
  /// odometer reading over summing recorded distances. Same logic as
  /// vehicle_detail_screen.dart's own [_currentMileage].
  double _mileageFor(Vehicle vehicle, List<Trip> trips) {
    for (final t in trips) {
      if (t.bleOdometerKm != null) return t.bleOdometerKm!;
    }
    final totalKm = trips.fold<double>(0, (sum, t) => sum + t.distanceMeters) / 1000.0;
    return (vehicle.startingOdometerKm ?? 0) + totalKm;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Garage'),
        actions: [
          IconButton(
            icon: const Icon(Ph.plus, size: 19),
            tooltip: 'Add vehicle',
            onPressed: _addVehicle,
          ),
          IconButton(
            icon: const Icon(Ph.userCircle, size: 20),
            tooltip: 'Account',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountScreen())),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
              children: [
                if (_vehicles.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text('No vehicles yet.', style: TextStyle(color: Noct.n500, fontSize: 13)),
                    ),
                  )
                else
                  for (final vehicle in _vehicles)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _VehicleRow(
                        vehicle: vehicle,
                        connected: vehicle.bleConnector == VehicleBleConnector.kawasakiRideology &&
                            _ble.isConnected &&
                            _connectingVehicleId == vehicle.id,
                        connecting: vehicle.bleConnector == VehicleBleConnector.kawasakiRideology &&
                            _ble.isBusy &&
                            _connectingVehicleId == vehicle.id,
                        mileageKm: _mileageFor(vehicle, _tripsByVehicle[vehicle.id] ?? const []),
                        tripCount: (_tripsByVehicle[vehicle.id] ?? const []).length,
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => VehicleDetailScreen(vehicle: vehicle))),
                        onTapConnection: () => _toggleConnection(vehicle),
                      ),
                    ),
                const SizedBox(height: 4),
                _AddVehicleControl(onTap: _addVehicle),
              ],
            ),
    );
  }
}

class _VehicleRow extends StatelessWidget {
  const _VehicleRow({
    required this.vehicle,
    required this.connected,
    required this.connecting,
    required this.mileageKm,
    required this.tripCount,
    required this.onTap,
    required this.onTapConnection,
  });

  final Vehicle vehicle;
  final bool connected;
  final bool connecting;
  final double mileageKm;
  final int tripCount;
  final VoidCallback onTap;
  final VoidCallback onTapConnection;

  @override
  Widget build(BuildContext context) {
    final supportsBle = vehicle.bleConnector == VehicleBleConnector.kawasakiRideology;
    final kmToService = vehicle.serviceIntervalKm == null
        ? null
        : (vehicle.lastServiceOdometerKm ?? vehicle.startingOdometerKm ?? 0) + vehicle.serviceIntervalKm! - mileageKm;

    // The name/icon area and the connection pill are two independent tap
    // targets (navigate vs. toggle BLE) — deliberately siblings, not one
    // nested inside the other's InkWell. Nesting two tap regions here
    // made the connection pill's own tap ambiguous with the row's
    // navigate-to-detail tap (both being simple, non-competing
    // TapGestureRecognizers in the same gesture arena), which is what
    // made BLE effectively unreachable from this row.
    return NoctPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(Noct.rMd),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: supportsBle ? Noct.a900 : Noct.n900,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: vehicle.photoPath != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(File(vehicle.photoPath!), width: 44, height: 44, fit: BoxFit.cover),
                              )
                            : Icon(
                                supportsBle ? Ph.motorcycle : Ph.car,
                                size: 22,
                                color: supportsBle ? Noct.a200 : Noct.n400,
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vehicle.name,
                              style: const TextStyle(fontSize: 15, color: Noct.text, fontWeight: FontWeight.w400),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              supportsBle ? '${vehicle.type.name} · Kawasaki Rideology BLE' : vehicle.type.name,
                              style: const TextStyle(fontSize: 11.5, color: Noct.n500),
                            ),
                          ],
                        ),
                      ),
                      if (!supportsBle) const SizedBox(width: 14),
                    ],
                  ),
                ),
              ),
              if (!supportsBle)
                const Padding(
                  padding: EdgeInsets.only(top: 15),
                  child: Icon(Ph.caretRight, size: 14, color: Noct.n600),
                )
              else
                InkWell(
                  onTap: onTapConnection,
                  borderRadius: BorderRadius.circular(Noct.rMd),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: connected
                        ? const _ConnectionPill()
                        : connecting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Noct.n500),
                          )
                        : const Icon(Ph.caretRight, size: 14, color: Noct.n600),
                  ),
                ),
            ],
          ),
          if (connected) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(value: mileageKm.toStringAsFixed(0), label: 'km on the clock'),
                ),
                Container(width: 1, height: 26, color: Noct.n800),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: _MiniStat(value: '$tripCount', label: 'Trips'),
                  ),
                ),
                Container(width: 1, height: 26, color: Noct.n800),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: _MiniStat(
                      value: kmToService == null ? '—' : kmToService.toStringAsFixed(0),
                      label: 'km to service',
                      valueColor: Noct.a300,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label, this.valueColor});
  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: Noct.stat(17, color: valueColor)),
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, letterSpacing: 0.9, color: Noct.n500)),
      ],
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: Noct.a900, borderRadius: BorderRadius.circular(6)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 6, height: 6, child: DecoratedBox(decoration: BoxDecoration(color: Noct.a400, shape: BoxShape.circle))),
          SizedBox(width: 6),
          Text('Connected', style: TextStyle(fontSize: 10.5, color: Noct.a200, fontWeight: FontWeight.w400)),
        ],
      ),
    );
  }
}

class _AddVehicleControl extends StatelessWidget {
  const _AddVehicleControl({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Noct.rMd),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          overlayColor: WidgetStatePropertyAll(Noct.accent.withValues(alpha: 0.05)),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Noct.rMd),
              border: Border.all(color: Noct.divider),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Ph.plus, size: 15, color: Noct.n300),
                SizedBox(width: 8),
                Text('Add a vehicle', style: TextStyle(fontSize: 13, color: Noct.n300, fontWeight: FontWeight.w400)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
