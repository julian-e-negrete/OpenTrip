import 'dart:async';
import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';

import '../trip/recording_controller.dart';

/// Keeps this app's process alive in the background for as long as the
/// Kawasaki BLE connection is open and no trip is being recorded — the
/// same proven mechanism trip recording already relies on (see
/// trip/location_recorder.dart's own foregroundNotificationConfig), just
/// triggered by BLE connection state instead of an active recording, and
/// with its own notification so it doesn't misleadingly say "recording"
/// when no trip is running.
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
/// Deliberately stands down whenever a trip is actively recording,
/// rather than running alongside it: geolocator_android exposes exactly
/// one native location stream (a single `EventChannel`, see that
/// package's `StreamHandlerImpl.onListen`/`onCancel`) — a second
/// concurrent `getPositionStream()` call doesn't add independent
/// protection, it *reconfigures that same shared stream* to whichever
/// call's settings arrived most recently, and cancelling one side can
/// tear the whole thing down for the other. Running this at the same
/// time as trip/location_recorder.dart's own stream starved a real
/// recording down to 3 GPS points over a 10-minute, 1.85km ride —
/// exactly this bug. A recording already runs its own foreground
/// service, so it needs no help from this one; this only ever fills the
/// gap a recording doesn't cover.
class BleKeepAliveService {
  BleKeepAliveService._() {
    RecordingController.instance.isRecording.addListener(_onRecordingChanged);
  }
  static final instance = BleKeepAliveService._();

  StreamSubscription<Position>? _sub;

  /// Whether BLE wants this running — distinct from [isActive], since the
  /// underlying stream stands down (without forgetting the request)
  /// whenever a recording is active. See class doc.
  bool _wantsActive = false;

  bool get isActive => _sub != null;

  Future<void> start() async {
    _wantsActive = true;
    await _applyDesiredState();
  }

  Future<void> stop() async {
    _wantsActive = false;
    await _applyDesiredState();
  }

  void _onRecordingChanged() => unawaited(_applyDesiredState());

  Future<void> _applyDesiredState() async {
    final shouldRun = _wantsActive && !RecordingController.instance.isRecording.value;
    if (shouldRun && _sub == null) {
      _sub = Geolocator.getPositionStream(locationSettings: _buildSettings()).listen((_) {}, onError: (_) {});
    } else if (!shouldRun && _sub != null) {
      await _sub?.cancel();
      _sub = null;
    }
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
