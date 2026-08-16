import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/auth_service.dart';
import 'auth/login_screen.dart';
import 'auth/supabase_not_configured_screen.dart';
import 'config/app_config.dart';
import 'home_shell.dart';
import 'logging/log_buffer.dart';

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
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true, brightness: Brightness.dark),
      home: AppConfig.isSupabaseConfigured ? const _AuthGate() : const SupabaseNotConfiguredScreen(),
    );
  }
}

/// Shows the login screen or the signed-in app shell, following Supabase's
/// auth-state stream so sign-in/sign-out anywhere (including a token
/// expiring) updates this immediately.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: AuthService.instance.onAuthStateChange,
      builder: (context, snapshot) {
        final signedIn = AuthService.instance.isSignedIn;
        return signedIn ? const HomeShell() : const LoginScreen();
      },
    );
  }
}
