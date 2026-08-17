import 'package:shared_preferences/shared_preferences.dart';

/// Whether auto-start drive detection is turned on — a per-device
/// setting, deliberately not synced (see data/models/user_profile.dart
/// for what does sync). Read from both the main isolate (the Account
/// tab's toggle) and the background task isolate
/// (autostart/driving_detector_task.dart, on every restart, to decide
/// whether it should even be running) — shared_preferences reads the
/// same on-disk file regardless of which isolate asks, same as
/// auth/current_user.dart's guest id already relies on.
class AutoStartPrefs {
  AutoStartPrefs._();

  static const _key = 'auto_start_enabled';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}
