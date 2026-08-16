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

    final googleSignIn = GoogleSignIn(serverClientId: AppConfig.googleWebClientId);
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

  Future<void> signOut() => _auth.signOut();
}
