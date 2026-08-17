import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import 'auth_service.dart';

/// Whoever local data (vehicles, trips) is scoped to — either a real
/// Supabase account, or a persistent locally-generated guest id.
///
/// Login was never meant to gate GPS recording, vehicle management, or the
/// BLE connector — those are entirely on-device features with no need for
/// a backend. This is what makes them testable with zero setup: every
/// screen that used to read `AuthService.instance.currentUser!.id`
/// directly (which crashes if Supabase was never configured) now goes
/// through here instead, which always resolves to *something* usable.
///
/// Signing in for real later doesn't automatically migrate guest-scoped
/// rows to the new account id — that's cloud sync's job (see
/// /docs/ROADMAP.md), not implemented yet.
class CurrentUser {
  CurrentUser._();
  static final instance = CurrentUser._();

  static const _guestIdKey = 'opentrip_guest_user_id';
  String? _cachedGuestId;

  Future<String> _ensureGuestId() async {
    final cached = _cachedGuestId;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_guestIdKey);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_guestIdKey, id);
    }
    _cachedGuestId = id;
    return id;
  }

  bool get _isReallySignedIn => AppConfig.isSupabaseConfigured && AuthService.instance.isSignedIn;

  /// The id every local vehicle/trip row is scoped to.
  Future<String> id() async {
    if (_isReallySignedIn) return AuthService.instance.currentUser!.id;
    return _ensureGuestId();
  }

  bool get isGuest => !_isReallySignedIn;

  /// Debug/fallback label — never shown as the primary identity in the UI
  /// (that's the local profile's display name; see
  /// data/models/user_profile.dart and home_shell.dart's Account tab,
  /// which deliberately never renders the raw email).
  String get debugLabel {
    if (_isReallySignedIn) {
      final user = AuthService.instance.currentUser!;
      return user.email ?? user.id;
    }
    return 'Guest (local testing mode)';
  }

  /// Generates and persists a fresh guest id, discarding the old one.
  /// Used after a guest deletes their local data, so a stray cached read
  /// of the old id can't resurrect wiped rows.
  Future<void> resetGuestId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = const Uuid().v4();
    await prefs.setString(_guestIdKey, id);
    _cachedGuestId = id;
  }
}
