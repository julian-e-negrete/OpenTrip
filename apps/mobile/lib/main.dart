import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/auth_service.dart';
import 'auth/login_screen.dart';
import 'config/app_config.dart';
import 'home_shell.dart';
import 'logging/log_buffer.dart';
import 'sync/sync_service.dart';
import 'theme/app_theme.dart';

void main() {
  // Capture every print() in the app — including flutter_blue_plus's own
  // verbose BLE-stack logging below — into logBuffer, in addition to the
  // normal console output. This is what makes the in-app Logs screen (on
  // the BLE tab) show low-level connection/GATT activity, not just our
  // own log lines.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterBluePlus.setLogLevel(LogLevel.verbose, color: false);

      if (AppConfig.isSupabaseConfigured) {
        await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
      }
      SyncService.instance.startListening();

      runApp(const OpenTripApp());
    },
    (error, stack) => logBuffer.add('UNCAUGHT ERROR: $error\n$stack'),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        parent.print(zone, line);
        logBuffer.add(line);
      },
    ),
  );
}

class OpenTripApp extends StatelessWidget {
  const OpenTripApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenTrip',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const _AuthGate(),
    );
  }
}

/// Decides between the login screen and the app shell. Two independent
/// ways to reach the shell: a real Supabase sign-in, or the "Continue
/// without an account" guest path (see auth/current_user.dart) — the
/// latter works even when Supabase was never configured for this build,
/// which is what makes every on-device feature (vehicles, GPS recording,
/// BLE) testable with zero backend setup.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _guestMode = false;

  void _continueAsGuest() => setState(() => _guestMode = true);

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.isSupabaseConfigured) {
      return _guestMode ? const HomeShell() : LoginScreen(onContinueAsGuest: _continueAsGuest);
    }
    return StreamBuilder<AuthState>(
      stream: AuthService.instance.onAuthStateChange,
      builder: (context, snapshot) {
        final signedIn = AuthService.instance.isSignedIn;
        if (signedIn || _guestMode) return const HomeShell();
        return LoginScreen(onContinueAsGuest: _continueAsGuest);
      },
    );
  }
}
