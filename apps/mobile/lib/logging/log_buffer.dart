import 'package:flutter/foundation.dart';

/// In-memory log of everything happening on the BLE connection —
/// every frame sent/received, handshake progress, scan/connect lifecycle
/// events, and uncaught errors (see main.dart's zone print capture).
///
/// A single app-wide instance so any screen can append to it without
/// threading state through the widget tree. See screens/log_screen.dart
/// for the viewer, which is how you get this off the phone: it's shown as
/// selectable text with a "copy all" button, so you can paste it directly
/// into a chat/issue without a computer.
class LogBuffer extends ChangeNotifier {
  static const _maxLines = 4000;
  final List<String> _lines = [];

  List<String> get lines => List.unmodifiable(_lines);

  bool get isEmpty => _lines.isEmpty;

  void add(String message) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    final ts = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.${three(now.millisecond)}';
    _lines.add('[$ts] $message');
    if (_lines.length > _maxLines) {
      _lines.removeRange(0, _lines.length - _maxLines);
    }
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }

  String get asText => _lines.join('\n');
}

/// App-wide log buffer instance.
final logBuffer = LogBuffer();
