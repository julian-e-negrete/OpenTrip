import 'package:flutter/foundation.dart';

/// Whether a trip is actively being recorded right now, shared between
/// [RecordingScreen] (which owns start/stop) and HomeShell's raised
/// record control (which just needs to know whether to draw the idle
/// circle or the pulsing "recording" square — see home_shell.dart).
class RecordingController {
  RecordingController._();
  static final instance = RecordingController._();

  final isRecording = ValueNotifier<bool>(false);
}
