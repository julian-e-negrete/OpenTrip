import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:kawasaki_rideology_ble/kawasaki_rideology_ble.dart';

String _normalizeUuid(String uuid) =>
    uuid.toLowerCase().replaceAll('-', '');

/// Concrete [BleTransport] built on `flutter_blue_plus`. This is the only
/// file in the app that imports a BLE plugin directly — the protocol
/// package itself stays plugin-agnostic (see its transport.dart), so
/// swapping BLE stacks later only means writing a new file like this one.
class FlutterBluePlusTransport implements BleTransport {
  FlutterBluePlusTransport(this.device);

  final BluetoothDevice device;

  BluetoothCharacteristic? _control;
  final List<BluetoothCharacteristic> _notifyChars = [];
  final _notifyController = StreamController<Uint8List>.broadcast();
  final List<StreamSubscription<List<int>>> _notifySubs = [];

  @override
  bool get isConnected => device.isConnected;

  @override
  Future<void> connect() async {
    if (!device.isConnected) {
      await device.connect(timeout: const Duration(seconds: 12));
    }
  }

  @override
  Future<void> disconnect() async {
    for (final sub in _notifySubs) {
      await sub.cancel();
    }
    _notifySubs.clear();
    if (device.isConnected) {
      await device.disconnect();
    }
  }

  @override
  Future<void> discoverServices() async {
    final services = await device.discoverServices();

    BluetoothService? target;
    for (final service in services) {
      if (_normalizeUuid(service.uuid.toString()) == _normalizeUuid(kServiceUuid)) {
        target = service;
        break;
      }
    }

    // Fall back to scanning every discovered service for the target
    // characteristics, in case this bike's GATT table doesn't group them
    // under the expected service UUID (mirrors the defensive fallback in
    // the upstream Python client this was ported from).
    final candidateServices = target != null ? [target] : services;

    for (final service in candidateServices) {
      for (final characteristic in service.characteristics) {
        final uuid = _normalizeUuid(characteristic.uuid.toString());
        if (uuid == _normalizeUuid(kControlCharacteristicUuid)) {
          _control = characteristic;
        }
        if (kNotifyCharacteristicUuids.map(_normalizeUuid).contains(uuid)) {
          _notifyChars.add(characteristic);
        }
      }
    }

    if (_control == null) {
      throw StateError(
        'Control characteristic $kControlCharacteristicUuid not found on this device — '
        'is this actually a Rideology-equipped bike?',
      );
    }
    if (_notifyChars.isEmpty) {
      throw StateError('No notify characteristics found under $kServiceUuid');
    }

    for (final characteristic in _notifyChars) {
      await characteristic.setNotifyValue(true);
      final sub = characteristic.onValueReceived.listen((value) {
        _notifyController.add(Uint8List.fromList(value));
      });
      _notifySubs.add(sub);
    }
  }

  @override
  Stream<Uint8List> get notifications => _notifyController.stream;

  @override
  Future<void> writeControlCharacteristic(Uint8List data, {required bool withResponse}) async {
    final control = _control;
    if (control == null) {
      throw StateError('Control characteristic not resolved — call discoverServices() first');
    }
    await control.write(data, withoutResponse: !withResponse);
  }
}
