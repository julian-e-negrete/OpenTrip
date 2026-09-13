import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_service.dart';
import '../config/app_config.dart';
import 'log_buffer.dart';

/// Batches logging/log_buffer.dart's lines up to Supabase's
/// `public.debug_log_lines` while signed in — see that table's own
/// comment in supabase/schema.sql for why this exists: error_logs.dart's
/// push only ever fires on a thrown exception, which misses a trip that
/// finishes completely normally (no exception anywhere) but recorded
/// zero GPS points the whole time. Reading this table directly (the
/// `supabase` MCP's execute_sql, same as error_logs) is what actually
/// lets a real on-device problem get diagnosed without asking the rider
/// to manually copy/paste the Debug Logs screen.
///
/// Deliberately buffers and flushes on a timer rather than one insert
/// per line — a live BLE connection can log several lines a second (see
/// kawasaki_client.dart's per-frame RX logging), and firing a network
/// request that often would be wasteful and could plausibly hit rate
/// limits on a long ride.
///
/// Same "guest data stays local-only" posture as every other table this
/// app syncs (sync/sync_service.dart) — a line logged while signed out
/// is simply never queued for Supabase at all (still written to the
/// on-device debug_log.txt as always, per log_buffer.dart), not queued
/// and sent retroactively after a later sign-in.
class LogSyncService {
  LogSyncService._();
  static final instance = LogSyncService._();

  static const _flushInterval = Duration(seconds: 20);
  // Caps memory if the device is offline for a long stretch — old lines
  // are dropped from the front rather than growing unboundedly. This is
  // a diagnostic aid, not a guarantee every single line ever reaches
  // Supabase; the on-device debug_log.txt (log_buffer.dart) remains the
  // actual complete record if a rider needs to pull it by hand.
  static const _maxPending = 2000;

  final _pending = <String>[];
  bool _listening = false;
  bool _flushing = false;

  bool get _canSync => AppConfig.isSupabaseConfigured && AuthService.instance.isSignedIn;

  /// Call once at app start (see main.dart), after logBuffer.init() so
  /// nothing already-queued races the subscription setup. Safe to call
  /// more than once.
  void startListening() {
    if (_listening) return;
    _listening = true;
    logBuffer.onLine.listen(_onLine);
    // Never cancelled — this is a singleton running for the app's whole
    // lifetime, same as SyncService's own realtime subscription.
    Timer.periodic(_flushInterval, (_) => unawaited(_flush()));

    // Sign-out drops whatever hadn't been sent yet, matching "guest data
    // stays local-only" — those lines were logged under a session that,
    // from this point on, isn't the one that would own them.
    AuthService.instance.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedOut) _pending.clear();
    });
  }

  void _onLine(String line) {
    if (!_canSync) return;
    _pending.add(line);
    if (_pending.length > _maxPending) {
      _pending.removeRange(0, _pending.length - _maxPending);
    }
  }

  Future<void> _flush() async {
    if (_flushing || !_canSync || _pending.isEmpty) return;
    _flushing = true;
    final batch = List<String>.of(_pending);
    _pending.clear();
    try {
      final userId = AuthService.instance.currentUser!.id;
      await Supabase.instance.client
          .from('debug_log_lines')
          .insert([for (final line in batch) {'user_id': userId, 'line': line}]);
    } catch (_) {
      // Best-effort, same posture as error_reporter.dart/sync_service.dart
      // — a diagnostic upload should never be allowed to throw into
      // whatever real app code triggered the log line in the first
      // place. Put the batch back so the next timer tick retries it,
      // capped by _maxPending same as any other pending line.
      _pending.insertAll(0, batch);
      if (_pending.length > _maxPending) {
        _pending.removeRange(0, _pending.length - _maxPending);
      }
    } finally {
      _flushing = false;
    }
  }
}
