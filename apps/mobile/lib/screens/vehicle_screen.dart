import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:kawasaki_rideology_ble/kawasaki_rideology_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import '../logging/log_buffer.dart';
import '../vehicle/flutter_blue_plus_transport.dart';
import 'log_screen.dart';

/// Minimal demo screen: scan for a Kawasaki Rideology-equipped bike,
/// connect, run the startup handshake, and show live telemetry. This is
/// the vehicle-connector slice only — see /docs/ROADMAP.md for how this
/// plugs into GPS trip recording.
class VehicleScreen extends StatefulWidget {
  const VehicleScreen({super.key});

  @override
  State<VehicleScreen> createState() => _VehicleScreenState();
}

enum _ConnectionState { idle, scanning, connecting, handshaking, connected, error }

class _VehicleScreenState extends State<VehicleScreen> {
  _ConnectionState _state = _ConnectionState.idle;
  String? _errorMessage;
  KawasakiClient? _client;
  RidingTelemetry? _telemetry;
  StreamSubscription<RidingTelemetry>? _telemetrySub;
  StreamSubscription<List<ScanResult>>? _scanSub;

  @override
  void dispose() {
    _telemetrySub?.cancel();
    _scanSub?.cancel();
    _client?.dispose();
    super.dispose();
  }

  Future<void> _scanAndConnect() async {
    setState(() {
      _state = _ConnectionState.scanning;
      _errorMessage = null;
    });
    logBuffer.add('--- New connection attempt ---');

    try {
      await _ensurePermissions();

      logBuffer.add('Scan: looking for a device advertising as ${kAdvertisedNamePrefixes.join(" or ")}…');
      final result = await _findBike();
      if (result == null) {
        logBuffer.add('Scan: timed out, no matching device found');
        setState(() {
          _state = _ConnectionState.error;
          _errorMessage = 'No Kawasaki-* bike found nearby. Make sure it\'s on and in range.';
        });
        return;
      }
      logBuffer.add(
        'Scan: found "${result.advertisementData.advName}" '
        '(${result.device.remoteId}), RSSI ${result.rssi}',
      );

      setState(() => _state = _ConnectionState.connecting);
      final transport = FlutterBluePlusTransport(result.device);
      final client = KawasakiClient(
        transport: transport,
        config: z500Er500fConfig,
        logger: logBuffer.add,
      );
      await client.connect();

      setState(() => _state = _ConnectionState.handshaking);
      await client.runStartupSequence();

      _telemetrySub = client.telemetry.listen((t) {
        if (mounted) setState(() => _telemetry = t);
      });

      setState(() {
        _client = client;
        _state = _ConnectionState.connected;
      });
    } catch (e) {
      logBuffer.add('ERROR: $e');
      setState(() {
        _state = _ConnectionState.error;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _ensurePermissions() async {
    logBuffer.add('Requesting Bluetooth scan/connect + location permissions…');
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    for (final entry in statuses.entries) {
      logBuffer.add('Permission ${entry.key}: ${entry.value}');
    }
  }

  Future<ScanResult?> _findBike() async {
    final completer = Completer<ScanResult?>();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName;
        if (name.isNotEmpty) {
          logBuffer.add('Scan: saw "$name" (${r.device.remoteId}), RSSI ${r.rssi}');
        }
        if (kAdvertisedNamePrefixes.any(name.startsWith)) {
          if (!completer.isCompleted) completer.complete(r);
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    final result = await completer.future.timeout(
      const Duration(seconds: 11),
      onTimeout: () => null,
    );
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle'),
        actions: [
          IconButton(
            icon: const Icon(Icons.article_outlined),
            tooltip: 'BLE logs',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LogScreen()),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: switch (_state) {
          _ConnectionState.connected => _TelemetryView(telemetry: _telemetry),
          _ConnectionState.error => _ErrorView(message: _errorMessage, onRetry: _scanAndConnect),
          _ConnectionState.idle => _IdleView(onScan: _scanAndConnect),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({required this.onScan});
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Connect a Kawasaki Rideology-equipped bike\n(currently: Z500 / Z500 ABS / Ninja 500 platform)',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onScan, child: const Text('Scan & connect')),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message ?? 'Something went wrong.', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _TelemetryView extends StatelessWidget {
  const _TelemetryView({required this.telemetry});
  final RidingTelemetry? telemetry;

  @override
  Widget build(BuildContext context) {
    final t = telemetry;
    if (t == null) {
      return const Center(child: Text('Connected — waiting for first telemetry frame…'));
    }
    return ListView(
      children: [
        if (t.modelName != null) _Row('Model', t.modelName!),
        if (t.vin != null) _Row('VIN', t.vin!),
        _Row('Speed', '${t.speedKph ?? '—'} km/h'),
        _Row('RPM', '${t.rpm ?? '—'}'),
        _Row('Gear', '${t.gear ?? '—'}'),
        _Row('Throttle', t.throttlePercent == null ? '—' : '${t.throttlePercent!.toStringAsFixed(0)} %'),
        _Row('Water temp', t.waterTemperatureC == null ? '—' : '${t.waterTemperatureC} °C'),
        _Row('Inlet air temp', t.inletAirTemperatureC == null ? '—' : '${t.inletAirTemperatureC} °C'),
        _Row('ECU battery', t.ecuBattery12V == null ? '—' : '${t.ecuBattery12V!.toStringAsFixed(2)} V'),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
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
