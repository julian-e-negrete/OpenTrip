import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Best-effort push of an error to Supabase's `error_logs` table (see
/// supabase/schema.sql), alongside whatever a call site already does
/// locally (typically a [logBuffer] line — see log_buffer.dart). The
/// point isn't replacing local logging, which only ever reaches whoever
/// is holding the phone right now — it's giving whoever has access to
/// the Supabase project (a developer, or an AI coding assistant working
/// from the project's own data) direct visibility into real on-device
/// failures with their context and stack trace, instead of only
/// reconstructing what might have happened from source code after the
/// fact.
///
/// Silently does nothing for a guest session (no Supabase session to
/// write with — same as every other table this app syncs, see
/// auth/current_user.dart). A real signed-in error that can't reach
/// Supabase right now (most commonly: a rider on the street with no
/// signal, exactly when something is most likely to actually go wrong)
/// is queued to a local file instead of being dropped — see [_enqueue]/
/// [flushPending] — so it still gets there once the app has a connection
/// again, rather than the failure being invisible forever. Never throws:
/// an error reporter that can itself cause a failure defeats the point.
abstract final class ErrorReporter {
  static File? _pendingFile;
  static bool _flushing = false;

  static Future<File> _file() async {
    final existing = _pendingFile;
    if (existing != null) return existing;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/pending_error_logs.jsonl');
    _pendingFile = file;
    return file;
  }

  /// [context] is a short, stable label for *where* this came from (e.g.
  /// "BLE auto-reconnect", "Camera: Overpass query") — grep-able across
  /// many rows, unlike the free-form [error] text.
  static Future<void> report(String context, Object error, [StackTrace? stack]) async {
    if (!AppConfig.isSupabaseConfigured) return;
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    final row = {
      'user_id': userId,
      // Explicit rather than relying on the column's own now() default —
      // a row queued here can sit in [_enqueue]'s local file for a long
      // time before [flushPending] actually gets it to Supabase (no
      // signal until well after the ride that caused it), and the
      // default would otherwise stamp every queued row with the flush
      // time instead of when it actually happened.
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
      'context': context,
      'message': error.toString(),
      'stack_trace': stack?.toString(),
      'platform': defaultTargetPlatform.name,
    };
    try {
      await client.from('error_logs').insert(row);
      // Already have a connection right now — good moment to also catch
      // up on anything queued from an earlier offline stretch.
      unawaited(flushPending());
    } catch (_) {
      await _enqueue(row);
    }
  }

  static Future<void> _enqueue(Map<String, dynamic> row) async {
    try {
      final file = await _file();
      await file.writeAsString('${jsonEncode(row)}\n', mode: FileMode.append, flush: false);
    } catch (_) {
      // Truly nothing left to try — see class doc, never throws.
    }
  }

  /// Retries whatever couldn't be sent earlier. Called after every
  /// successful [report] and from sync_service.dart's own sign-in
  /// listener, since a cold app start with a signal is the most likely
  /// moment connectivity actually came back after an offline ride.
  static Future<void> flushPending() async {
    if (!AppConfig.isSupabaseConfigured || _flushing) return;
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) return;
    _flushing = true;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final lines = await file.readAsLines();
      if (lines.isEmpty) return;
      final stillPending = <String>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final row = jsonDecode(line) as Map<String, dynamic>;
          await client.from('error_logs').insert(row);
        } catch (_) {
          stillPending.add(line);
        }
      }
      await file.writeAsString(stillPending.isEmpty ? '' : '${stillPending.join('\n')}\n');
    } catch (_) {
      // Best-effort — see class doc.
    } finally {
      _flushing = false;
    }
  }
}
