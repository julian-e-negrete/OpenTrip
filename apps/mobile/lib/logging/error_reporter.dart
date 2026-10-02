import 'package:flutter/foundation.dart';
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
/// auth/current_user.dart) or if the write itself fails. Never throws:
/// an error reporter that can itself cause a failure defeats the point.
abstract final class ErrorReporter {
  /// [context] is a short, stable label for *where* this came from (e.g.
  /// "BLE auto-reconnect", "Camera: Overpass query") — grep-able across
  /// many rows, unlike the free-form [error] text.
  static Future<void> report(String context, Object error, [StackTrace? stack]) async {
    if (!AppConfig.isSupabaseConfigured) return;
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;
      await client.from('error_logs').insert({
        'user_id': userId,
        'context': context,
        'message': error.toString(),
        'stack_trace': stack?.toString(),
        'platform': defaultTargetPlatform.name,
      });
    } catch (_) {
      // Best-effort — see class doc.
    }
  }
}
