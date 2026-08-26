import 'dart:io' show Platform;

import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Thin wrapper around Supabase Auth. Two sign-in paths, matching what was
/// asked for: native Google sign-in (via an ID token, so there's no
/// in-app browser redirect to manage) and passwordless email — a 6-digit
/// one-time code rather than a magic link, which avoids needing deep-link
/// handling in the app.
///
/// Every method here assumes Supabase.initialize() already ran — see
/// main.dart, which only does that when [AppConfig.isSupabaseConfigured].
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  GoTrueClient get _auth => _client.auth;

  User? get currentUser => _auth.currentUser;

  bool get isSignedIn => currentUser != null;

  /// Fires on sign-in, sign-out, and token refresh.
  Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;

  /// Step 1 of Google sign-in: get an ID token from the native Google
  /// account picker, then hand it to Supabase. Returns null if the user
  /// cancelled the picker (not an error).
  Future<AuthResponse?> signInWithGoogle() async {
    if (!AppConfig.isGoogleSignInConfigured) {
      throw StateError(
        'Google sign-in isn\'t configured for this build. Rebuild with '
        '--dart-define=GOOGLE_WEB_CLIENT_ID=... — see docs/AUTH_SETUP.md.',
      );
    }

    // clientId is "not supported on all platforms (e.g. Android)" per the
    // google_sign_in package itself — Android resolves its client purely
    // from the package name + SHA-1 registered in Google Cloud Console,
    // never from a value in code, so this is iOS-only on purpose (see
    // AppConfig.googleIosClientId's doc comment for why iOS needs it at
    // all). Unverified on a real device — this project has no way to
    // build/run iOS yet (see docs/IOS_TESTING_SETUP.md).
    final googleSignIn = GoogleSignIn(
      serverClientId: AppConfig.googleWebClientId,
      clientId: Platform.isIOS && AppConfig.googleIosClientId.isNotEmpty ? AppConfig.googleIosClientId : null,
    );
    final account = await googleSignIn.signIn();
    if (account == null) return null; // user cancelled

    final googleAuth = await account.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) {
      throw StateError('Google returned no ID token — check the Android OAuth client setup.');
    }

    return _auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken);
  }

  /// Step 1 of email sign-in: send a 6-digit code to [email]. Call
  /// [verifyEmailCode] with what the user types back to complete it.
  Future<void> sendEmailCode(String email) {
    return _auth.signInWithOtp(email: email);
  }

  Future<AuthResponse> verifyEmailCode({required String email, required String code}) {
    return _auth.verifyOTP(type: OtpType.email, email: email, token: code);
  }

  /// Best-effort: stores the display name in Supabase's user metadata too
  /// (`auth.users.raw_user_meta_data`), so it's already in the right place
  /// once a cloud profile/leaderboard exists to show it (see
  /// data/models/user_profile.dart — the local copy is authoritative for
  /// display today). Failures here shouldn't block saving the local
  /// profile, so callers should treat this as fire-and-forget.
  Future<void> updateDisplayName(String name) {
    return _auth.updateUser(UserAttributes(data: {'display_name': name}));
  }

  Future<void> signOut() => _auth.signOut();
}
