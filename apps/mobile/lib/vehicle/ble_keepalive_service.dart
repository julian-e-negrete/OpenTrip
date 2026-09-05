import 'dart:async';
import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';

/// Keeps this app's process alive in the background for as long as the
/// Kawasaki BLE connection is open — the same proven mechanism trip
/// recording already relies on (see trip/location_recorder.dart's own
/// foregroundNotificationConfig), just triggered by BLE connection state
/// instead of an active recording, and with its own notification so it
/// doesn't misleadingly say "recording" when no trip is running.
///
/// A BLE GATT connection has no protection of its own: unlike a trip
/// recording (already a foreground service), simply holding a Bluetooth
/// connection open while the app is backgrounded gives Android's
/// memory-pressure/Doze process killing nothing to respect — the whole
/// process, and with it the connection, can be torn down silently. This
/// doesn't *record* location — a large distanceFilter and long interval,
/// reduced accuracy — it only needs geolocator's foreground-service side
/// effect, not the position data itself, which is why every update is
/// simply discarded.
///
/// Deliberately independent of trip recording: if both are active at
/// once, two separate persistent notifications show rather than one
/// combined one. That's a minor redundancy, not a conflict — Android
/// supports multiple concurrent location requests from the same app —
/// and it avoids the two features needing to coordinate ownership of a
/// single shared service.
class BleKeepAliveService {
  BleKeepAliveService._();
  static final instance = BleKeepAliveService._();

  StreamSubscription<Position>? _sub;

  bool get isActive => _sub != null;

  Future<void> start() async {
    if (_sub != null) return;
    _sub = Geolocator.getPositionStream(locationSettings: _buildSettings()).listen(
      (_) {},
      onError: (_) {},
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  LocationSettings _buildSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.reduced,
        distanceFilter: 500,
        intervalDuration: const Duration(seconds: 30),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'OpenTrip is connected to your bike',
          notificationText: 'Keeping the Bluetooth connection alive — tap to return to the app.',
          enableWakeLock: true,
        ),
      );
    }
    // iOS unverified — this project has no way to build/run iOS (needs a
    // Mac; see /README.md). Background BLE on iOS works through a
    // different mechanism entirely (a declared "bluetooth-central"
    // background mode, not a location foreground service), so this
    // fallback is best-effort, not a real solution there.
    return const LocationSettings(accuracy: LocationAccuracy.reduced, distanceFilter: 500);
  }
}
