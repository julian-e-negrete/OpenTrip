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

  static bool get isSupabaseConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get isGoogleSignInConfigured => googleWebClientId.isNotEmpty;
}
