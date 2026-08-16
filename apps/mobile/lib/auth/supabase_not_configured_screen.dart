import 'package:flutter/material.dart';

/// Shown instead of the login screen when the app was built without
/// --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... .
/// The point is to fail loud and explain the fix, not show a blank screen
/// or crash — see /docs/AUTH_SETUP.md for the actual setup steps.
class SupabaseNotConfiguredScreen extends StatelessWidget {
  const SupabaseNotConfiguredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.settings_outlined, size: 48),
              SizedBox(height: 16),
              Text(
                'Login isn\'t configured yet',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12),
              Text(
                'This build has no Supabase project wired up, so Google/email '
                'sign-in can\'t work yet. This app is free and open source, so '
                'there\'s no shared backend — you (or whoever built this APK) '
                'need to create your own free Supabase project and rebuild '
                'with:\n\n'
                'flutter build apk --dart-define=SUPABASE_URL=... '
                '--dart-define=SUPABASE_ANON_KEY=... '
                '--dart-define=GOOGLE_WEB_CLIENT_ID=...\n\n'
                'Full steps are in docs/AUTH_SETUP.md in the repo.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
