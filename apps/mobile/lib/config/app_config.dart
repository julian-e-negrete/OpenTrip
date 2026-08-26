/// Build-time configuration. Nothing here is a secret checked into source —
/// every value is read from `--dart-define` at build time, so the actual
/// project URL/keys live in your build command (or your CI secrets), never
/// in git. See /docs/AUTH_SETUP.md for how to get these values and the
/// exact `flutter build` / `flutter run` invocation that supplies them.
abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// The **Web** OAuth client ID from Google Cloud Console — this is the
  /// one Supabase's Google provider is configured with, and it's what
  /// `google_sign_in` needs as `serverClientId` so the ID token it gets is
  /// valid for Supabase to accept. This is deliberately not the Android
  /// client ID (that one only needs to exist in Google Cloud Console with
  /// the app's package name + SHA-1; it's never referenced in code).
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// The **iOS** OAuth client ID from Google Cloud Console — unlike
  /// Android (where the client only needs to exist registered against
  /// the app's package name + SHA-1, and is never referenced in code),
  /// `google_sign_in` on iOS needs its own client's ID passed explicitly
  /// as `clientId`, plus that same client's reversed form registered as
  /// a URL scheme in ios/Runner/Info.plist so the sign-in redirect can
  /// return to the app. See docs/AUTH_SETUP.md. Optional — guest mode
  /// (auth/current_user.dart) works without any of this, so an iOS build
  /// missing this can still be tested end-to-end.
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  static bool get isSupabaseConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get isGoogleSignInConfigured => googleWebClientId.isNotEmpty;
}
