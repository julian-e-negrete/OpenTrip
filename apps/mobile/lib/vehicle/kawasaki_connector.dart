import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:kawasaki_rideology_ble/kawasaki_rideology_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import 'flutter_blue_plus_transport.dart';

/// Scans for, connects to, and runs the startup handshake against a
/// Kawasaki Rideology-equipped bike. Shared by every path that can
/// trigger a connection — the vehicle row's connection pill
/// (vehicles/vehicle_list_screen.dart) and the trip recorder's optional
/// live-telemetry hookup (trip/recording_screen.dart) — so all of them
/// behave identically and this logic exists in exactly one place.
class KawasakiConnector {
  KawasakiConnector._();

  static Future<void> ensurePermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  /// Returns null if no matching device was found within [scanTimeout].
  static Future<ScanResult?> findBike({
    Duration scanTimeout = const Duration(seconds: 10),
    void Function(String)? onLog,
  }) async {
    final completer = Completer<ScanResult?>();
    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName;
        if (name.isNotEmpty) {
          onLog?.call('Scan: saw "$name" (${r.device.remoteId}), RSSI ${r.rssi}');
        }
        if (kAdvertisedNamePrefixes.any(name.startsWith)) {
          if (!completer.isCompleted) completer.complete(r);
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: scanTimeout);
    final result = await completer.future.timeout(
      scanTimeout + const Duration(seconds: 1),
      onTimeout: () => null,
    );
    await FlutterBluePlus.stopScan();
    await sub.cancel();
    return result;
  }

  /// Connects and runs the startup handshake against [result]. Throws on
  /// failure (timeout, GATT error, unexpected device) — callers decide
  /// whether that should be fatal (the demo screen) or non-fatal (the trip
  /// recorder, which should still record GPS-only if the bike doesn't
  /// cooperate).
  static Future<KawasakiClient> connect({
    required ScanResult result,
    void Function(String)? onLog,
  }) async {
    final transport = FlutterBluePlusTransport(result.device);
    final client = KawasakiClient(transport: transport, config: z500Er500fConfig, logger: onLog);
    await client.connect();
    await client.runStartupSequence();
    return client;
  }
}
