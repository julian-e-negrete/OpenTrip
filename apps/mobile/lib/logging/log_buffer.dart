import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// In-memory log of everything happening on the BLE connection —
/// every frame sent/received, handshake progress, scan/connect lifecycle
/// events, and uncaught errors (see main.dart's zone print capture).
///
/// Also mirrored to a local file (see [init]) — a rider with a real
/// problem to diagnose is usually on the street with no signal at the
/// time, unable to check the in-app Log screen mid-ride, and a crash or
/// forced process kill wipes this in-memory list before anyone gets the
/// chance to look at it anyway. Persisting to disk means whatever just
/// happened is still there the next time the app opens, signal or not —
/// offline-first, unlike error_reporter.dart's Supabase push (which now
/// also queues locally rather than dropping on failure — see that file).
///
/// Also mirrored to Supabase while signed in (logging/log_sync_service.dart
/// subscribes to [onLine] and batches it up) — error_logs.dart's push only
/// ever fires on a thrown exception, which turned out to miss a real class
/// of bug: a trip that finishes completely normally (no exception anywhere)
/// but recorded zero GPS points the whole time was otherwise undiagnosable
/// without asking the rider to manually copy/paste this screen's contents.
///
/// A single app-wide instance so any screen can append to it without
/// threading state through the widget tree. See screens/log_screen.dart
/// for the viewer, which is how you get this off the phone: it's shown as
/// selectable text with a "copy all" button, so you can paste it directly
/// into a chat/issue without a computer.
class LogBuffer extends ChangeNotifier {
  static const _maxLines = 4000;
  // How many appends between full-file rewrites — the file is trimmed to
  // the in-memory _lines (already capped at _maxLines) each time, so this
  // just controls how often that rewrite happens rather than doing one on
  // every single line once the buffer is full.
  static const _rewriteEvery = 500;
  final List<String> _lines = [];

  File? _file;
  int _appendsSinceRewrite = 0;

  // Every call to add() fires its own unawaited disk write — with
  // nothing serializing them, a fast burst of log lines (very real:
  // permission checks, GPS fix acceptance, and BLE frame logs can all
  // land within the same event-loop turn) could run their
  // File.writeAsString calls concurrently, and a periodic full-file
  // rewrite (see _rewriteEvery below) racing against a still-in-flight
  // append truncated/interleaved lines — confirmed live: a "GPS: battery
  // optimization exemption after request: PermissionStatus.granted"
  // line came back on disk as just "r request: PermissionStatus.granted",
  // missing everything before it. Chaining every write onto this future
  // instead of firing them independently guarantees one write fully
  // finishes before the next starts, so lines can no longer land out of
  // order or torn.
  Future<void> _writeQueue = Future.value();

  // Separate from the ChangeNotifier above (which just says "something
  // changed," fine for a UI rebuild but not enough to tell a listener
  // *which* lines are new) — logging/log_sync_service.dart subscribes to
  // this instead of diffing `lines` against a remembered index, which
  // would need extra bookkeeping to stay correct across the trim in
  // [add] once the buffer hits _maxLines.
  final _lineController = StreamController<String>.broadcast();
  Stream<String> get onLine => _lineController.stream;

  List<String> get lines => List.unmodifiable(_lines);

  bool get isEmpty => _lines.isEmpty;

  /// Loads whatever was on disk from a previous run before this instance
  /// starts adding to it — call once, early in main(), before anything
  /// else might call [add]. Safe to fail silently: this is a diagnostic
  /// aid, not something the app depends on to function, and the in-memory
  /// buffer still works for the rest of this session either way.
  Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/debug_log.txt');
      final file = _file!;
      if (await file.exists()) {
        final existing = await file.readAsLines();
        _lines.addAll(existing.length > _maxLines ? existing.sublist(existing.length - _maxLines) : existing);
      }
    } catch (_) {
      _file = null;
    }
  }

  void add(String message) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    final ts = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.${three(now.millisecond)}';
    final line = '[$ts] $message';
    _lines.add(line);
    if (_lines.length > _maxLines) {
      _lines.removeRange(0, _lines.length - _maxLines);
    }
    notifyListeners();
    _lineController.add(line);
    _enqueue(() => _persist(line));
  }

  /// Chains [op] onto the write queue so it only ever runs once every
  /// earlier queued write has actually finished — see _writeQueue's doc
  /// comment. Swallows errors from the queue itself so one failed write
  /// (a full disk, a transient IO error) can't wedge every write after
  /// it — [_persist]/[_clearFile] already catch their own errors, this
  /// is just insurance for the chain itself.
  void _enqueue(Future<void> Function() op) {
    _writeQueue = _writeQueue.then((_) => op()).catchError((_) {});
  }

  Future<void> _persist(String line) async {
    final file = _file;
    if (file == null) return;
    try {
      _appendsSinceRewrite++;
      if (_appendsSinceRewrite >= _rewriteEvery) {
        _appendsSinceRewrite = 0;
        await file.writeAsString('${_lines.join('\n')}\n', flush: false);
      } else {
        await file.writeAsString('$line\n', mode: FileMode.append, flush: false);
      }
    } catch (_) {
      // Best-effort — see class doc.
    }
  }

  void clear() {
    _lines.clear();
    notifyListeners();
    final file = _file;
    if (file != null) _enqueue(() => _clearFile(file));
  }

  Future<void> _clearFile(File file) async {
    try {
      await file.writeAsString('');
    } catch (_) {
      // Best-effort — see class doc.
    }
  }

  String get asText => _lines.join('\n');
}

/// App-wide log buffer instance.
final logBuffer = LogBuffer();
