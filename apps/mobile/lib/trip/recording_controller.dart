import 'package:flutter/foundation.dart';

/// Whether a trip is actively being recorded right now, shared between
/// [RecordingScreen] (which owns start/stop) and HomeShell's raised
/// record control (which just needs to know whether to draw the idle
/// circle or the pulsing "recording" square — see home_shell.dart).
class RecordingController {
  RecordingController._();
  static final instance = RecordingController._();

  final isRecording = ValueNotifier<bool>(false);

  /// Set by HomeShell's state so screens with no direct access to the
  /// shell (e.g. Trips' empty state) can still open the Record overlay,
  /// same as tapping the raised control.
  VoidCallback? openRecordScreen;

  /// Set by RecordingScreen's state — what the shell's raised control
  /// actually calls to start/stop a trip once the Record screen is
  /// already showing (see home_shell.dart's onTapRecord).
  VoidCallback? onRequestStart;
  VoidCallback? onRequestStop;
}
