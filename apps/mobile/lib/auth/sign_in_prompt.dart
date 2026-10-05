import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';
import '../theme/primitives.dart';
import 'auth_service.dart';
import 'login_screen.dart';

/// Opens the login screen on top of whatever's showing, and closes it again
/// by itself once sign-in succeeds — LoginScreen has no "done" step of its
/// own (as the app's first screen it's simply replaced by the shell), so a
/// pushed copy would otherwise sit there after a successful sign-in still
/// offering "Continue without an account". Completes with whether the
/// rider ended up signed in.
Future<bool> pushSignIn(BuildContext context) async {
  final navigator = Navigator.of(context);
  StreamSubscription<Object>? sub;
  Route<void>? route;
  route = MaterialPageRoute<void>(
    builder: (_) => LoginScreen(onContinueAsGuest: () => navigator.pop()),
  );
  if (AppConfig.isSupabaseConfigured) {
    sub = AuthService.instance.onAuthStateChange.listen((_) {
      final r = route;
      if (!AuthService.instance.isSignedIn || r == null || !r.isActive) return;
      if (r.isCurrent) {
        navigator.pop();
      } else {
        // Something (e.g. an email-code step) is on top of it.
        navigator.removeRoute(r);
      }
    });
  }
  try {
    await navigator.push(route);
  } finally {
    await sub?.cancel();
  }
  return AppConfig.isSupabaseConfigured && AuthService.instance.isSignedIn;
}

/// The guest-mode placeholder for features that need an account (ranks,
/// territory, friends, crews): what the feature is, and a way to actually
/// sign in from right there instead of a dead end. On a build without
/// Supabase configured there's nothing to sign in to, so it says that
/// instead of offering a button that can't work.
class SignInPrompt extends StatelessWidget {
  const SignInPrompt({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.onSignedIn,
  });

  final IconData icon;
  final String title;
  final String message;

  /// Called after a successful sign-in, so the host screen can reload.
  final VoidCallback? onSignedIn;

  @override
  Widget build(BuildContext context) {
    final canSignIn = AppConfig.isSupabaseConfigured;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: Noct.a900, shape: BoxShape.circle),
              child: Icon(icon, size: 24, color: Noct.a300),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: Noct.text),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, height: 1.45, color: Noct.n400),
            ),
            const SizedBox(height: 22),
            if (canSignIn)
              NoctOutlinedButton(
                label: 'Sign in',
                expand: false,
                onPressed: () async {
                  final signedIn = await pushSignIn(context);
                  if (signedIn) onSignedIn?.call();
                },
              )
            else
              const Text(
                'Sign-in isn\'t set up in this build.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Noct.n500),
              ),
          ],
        ),
      ),
    );
  }
}
