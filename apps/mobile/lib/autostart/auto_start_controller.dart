import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../data/data_events.dart';
import '../logging/log_buffer.dart';
import '../trip/location_recorder.dart';
import 'auto_start_prefs.dart';
import 'driving_detector_task.dart';

/// Main-isolate control surface for auto-start drive detection — the
/// Account tab's toggle talks to this, not to
/// autostart/driving_detector_task.dart directly (that class only ever
/// runs in the background isolate flutter_foreground_task spawns; see its
/// doc comment). Owns permission requests (the ones that need a
/// foreground Activity to show a dialog, which the background isolate
/// can't do itself) and starting/stopping the actual background service.
class AutoStartController {
  AutoStartController._();
  static final instance = AutoStartController._();

  bool _initialized = false;

  void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'opentrip_auto_start',
        channelName: 'Auto-start drive detection',
        channelDescription: 'Watches for driving so a trip can start automatically, even if the app is closed.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        // The whole point of this feature (per user choice — see
        // docs/ROADMAP.md) — survive the app being swiped away from
        // Recents, unlike trip/location_recorder.dart's own foreground
        // service, which doesn't.
        stopWithTask: false,
      ),
    );
  }

  Future<bool> isEnabled() => AutoStartPrefs.isEnabled();

  /// Call once at app start (main.dart), regardless of whether the
  /// feature is on — re-attaches the data callback (a fresh app launch
  /// has no listeners registered yet even if the background service is
  /// already running from before) and re-applies the same init() config
  /// so isRunningService/updateService calls are valid.
  void attachAtStartup() {
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    _ensureInitialized();
  }

  /// The other end of trip/location_recorder.dart's `onLog` bridge and
  /// autostart/driving_detector_task.dart's own `_log` calls — everything
  /// that isolate reports lands here and gets folded into the same
  /// [logBuffer] screens/log_screen.dart shows, prefixed so it's obvious
  /// in the log which subsystem is background vs. foreground.
  void _onTaskData(Object data) {
    if (data is! Map) return;
    switch (data['event']) {
      case 'autoTripStarted':
      case 'autoTripFinished':
        DataEvents.instance.notifyChanged();
      case 'log':
        final message = data['message'];
        if (message is String) logBuffer.add('[bg] $message');
    }
  }

  /// Requests every permission this needs, then starts the background
  /// service. Returns an explanatory message on failure, or null on
  /// success — the Account tab shows whichever it gets back.
  Future<String?> enable() async {
    _ensureInitialized();

    var activityPermission = await FlutterActivityRecognition.instance.checkPermission();
    if (activityPermission == ActivityPermission.DENIED) {
      activityPermission = await FlutterActivityRecognition.instance.requestPermission();
    }
    if (activityPermission != ActivityPermission.GRANTED) {
      return 'Activity permission is required for auto-start — grant it in system settings.';
    }

    try {
      // Same permissions a manual recording needs (location + Android
      // 13+ notification) — the background task can't show these dialogs
      // itself, so they need to already be resolved before it ever tries
      // to record.
      await LocationRecorder.ensureReady();
    } catch (e) {
      return e.toString();
    }

    var notificationPermission = await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      notificationPermission = await FlutterForegroundTask.requestNotificationPermission();
    }

    // Not required for the service to start, but several OEMs (Xiaomi,
    // Huawei, Samsung, OnePlus, and others) kill background services
    // more aggressively than stock Android's own Doze/App Standby does,
    // regardless of stopWithTask/foreground-service status — exemption
    // from battery optimization is the one lever available in-app
    // against that. Best-effort: declining this doesn't block enabling
    // the feature, it just means it's more likely to get killed on an
    // aggressive OEM skin.
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
    } else {
      final result = await FlutterForegroundTask.startService(
        serviceId: 257,
        serviceTypes: const [ForegroundServiceTypes.location],
        notificationTitle: 'OpenTrip',
        notificationText: 'Watching for driving…',
        callback: startDrivingDetectorTask,
      );
      if (result is ServiceRequestFailure) {
        return 'Couldn\'t start auto-start detection: ${result.error}';
      }
    }

    await AutoStartPrefs.setEnabled(true);
    return null;
  }

  Future<void> disable() async {
    await AutoStartPrefs.setEnabled(false);
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}
