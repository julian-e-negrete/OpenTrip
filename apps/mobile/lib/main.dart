import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/auth_service.dart';
import 'auth/login_screen.dart';
import 'config/app_config.dart';
import 'home_shell.dart';
import 'logging/error_reporter.dart';
import 'logging/log_buffer.dart';
import 'logging/log_sync_service.dart';
import 'sync/sync_service.dart';
import 'theme/app_theme.dart';
import 'theme/layout_prefs.dart';

void main() {
  // Capture every print() in the app — including flutter_blue_plus's own
  // BLE-stack logging below — into logBuffer, in addition to the normal
  // console output. This is what makes the in-app Logs screen show
  // low-level connection activity, not just our own log lines.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // Loads whatever logBuffer.dart persisted from a previous run
      // before anything else can start adding to it — see that file's
      // doc comment for why this exists (a crash or restart on the
      // street, no signal, otherwise loses the in-memory log for good).
      await logBuffer.init();
      // Flutter's own default for this (dump to console, keep going) stays
      // in effect via presentError — this just additionally captures the
      // same framework-level errors (failed builds, layout exceptions)
      // that runZonedGuarded's handler below never sees, since Flutter
      // catches those itself rather than letting them escape the zone.
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        logBuffer.add('FLUTTER ERROR: ${details.exception}\n${details.stack}');
        unawaited(ErrorReporter.report('Flutter framework error', details.exception, details.stack));
      };
      // `.verbose` was logging every single GATT characteristic-received
      // frame (the bike's ECU sends telemetry over BLE multiple times a
      // second) straight into logBuffer's persisted, size-capped ring
      // buffer. On a real BLE-connected ride this flooded out everything
      // else within under an hour — a rider's own debug log came back
      // 87% raw BLE frame dumps with only 2 surviving GPS lines out of a
      // full 4000-line buffer, destroying the log's usefulness for
      // diagnosing exactly the class of problem (GPS/recording) it's
      // meant to help with. `.warning` keeps real BLE-stack failures
      // visible without the per-frame noise; this app's own connection
      // lifecycle messages (see ble_connection_service.dart's "BLE:
      // connection lost/reconnected/..." lines) are separate explicit
      // logBuffer.add() calls, unaffected by this setting either way.
      FlutterBluePlus.setLogLevel(LogLevel.warning, color: false);

      if (AppConfig.isSupabaseConfigured) {
        await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
      }
      SyncService.instance.startListening();
      // After logBuffer.init() above, so nothing already-queued this
      // session races the subscription setup — see that service's own
      // doc comment for why this exists.
      LogSyncService.instance.startListening();
      // Loaded before the first frame so no screen flashes a default
      // layout variant and then jumps once this resolves.
      await LayoutPrefs.instance.load();

      runApp(const OpenTripApp());
    },
    (error, stack) {
      // supabase_flutter's own background session-refresh timer retries
      // on a short interval with no backoff, and every failed attempt
      // while offline throws here — completely expected on a ride with
      // no signal (exactly the "no internet on the street" case this
      // app is built around), not a real bug. Logging it the same way
      // as a genuine crash — full stack trace to logBuffer, a row to
      // error_logs — turned one 17-minute dead zone into 166 near-
      // identical rows: over 2800 of a 4000-line local log buffer, and
      // (since ErrorReporter.report itself can't reach Supabase either
      // while offline) 166 duplicate entries queued to flush into
      // error_logs the moment connectivity returned. A single compact
      // line is enough to show it happened without drowning out
      // whatever else was going on during that stretch.
      if (error is AuthRetryableFetchException) {
        logBuffer.add('Auth: session refresh failed while offline — ${error.message}');
        return;
      }
      logBuffer.add('UNCAUGHT ERROR: $error\n$stack');
      unawaited(ErrorReporter.report('Uncaught error', error, stack));
    },
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
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
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
