import 'dart:typed_data';

/// What [KawasakiClient] needs from a BLE stack. The app supplies a
/// concrete implementation (e.g. wrapping `flutter_blue_plus`); this
/// package never imports a BLE plugin directly, which keeps it testable
/// with plain `dart test` and swappable across BLE backends.
///
/// Implementations are expected to already know which device they're
/// talking to (constructed with a device handle/address) — this interface
/// only covers what happens *after* a device has been chosen from a scan.
abstract class BleTransport {
  /// Open a GATT connection to the device.
  Future<void> connect();

  Future<void> disconnect();

  bool get isConnected;

  /// Fires `false` whenever the GATT link drops — including when the
  /// bike goes out of range, its own firmware sleeps, or Android itself
  /// tears down the connection — not just on an explicit [disconnect]
  /// call. Callers that want to tell "I asked to disconnect" apart from
  /// "it dropped on its own" need to track that themselves; this stream
  /// only reports the link's actual state.
  Stream<bool> get connectionState;

  /// Discover services/characteristics. Must resolve, at minimum, the
  /// control characteristic and the notify characteristics under
  /// [kServiceUuid] (see protocol_ids.dart) before this returns —
  /// implementations may fall back to raw UUID lookups if a bike's GATT
  /// table doesn't group them under the expected service, mirroring the
  /// defensive fallback in the upstream Python client.
  Future<void> discoverServices();

  /// Subscribe to notifications on all three Rideology notify
  /// characteristics. Must be called after [discoverServices]. Each event
  /// is one raw frame's bytes (frame ID as the first byte).
  Stream<Uint8List> get notifications;

  /// Write a raw frame to the control characteristic.
  Future<void> writeControlCharacteristic(Uint8List data, {required bool withResponse});
}
