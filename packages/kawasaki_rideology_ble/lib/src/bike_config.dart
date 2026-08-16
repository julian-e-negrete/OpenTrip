// Per-bike tuning knobs. Structurally mirrors the JSON config format from
// custom_components/kawasaki/configs/*.json in
// https://github.com/Zen3515/homeassistant-kawasaki-rideology-ble
// (Apache License 2.0) — see /NOTICE.md — but compiled in as a Dart const
// rather than loaded as a JSON asset, so the package has no asset-bundling
// requirement.
//
// Different Kawasaki models expose different subsets of telemetry (an EV
// has no RPM, a bike with no lean sensor never fills that field, etc). The
// 0x40 frame tells you at runtime which fields *your specific unit*
// supports — `supportedFields` here is what has been observed/assumed for
// this model and is used as a fallback allowlist before that live
// negotiation completes.

class BikeConfig {
  /// Human-readable model name, e.g. "Kawasaki-ER500F".
  final String model;

  /// Frame IDs sent, in order, right after connecting — mirrors what the
  /// official app does so the bike doesn't reject an unfamiliar sequence.
  final List<int> startupFrames;

  /// Frames in [startupFrames] that should NOT block waiting for a
  /// response (some bikes never ACK certain optional frames).
  final Set<int> startupNoWaitFrames;

  final bool controlWriteWithResponse;
  final bool requireStartupResponses;
  final Duration startupWaitTimeout;
  final Duration startupInterFrameDelay;
  final int startupRetries;
  final Duration startupRetryDelay;

  /// 'auto' | 'raw' | 'quarter' — see parseRpm.
  final String rpmMode;

  /// 'auto' | 'raw' | 'scaled' | 'raw1' — see parseWheelSpeedKph.
  final String wheelMode;

  /// Per-field support map for this model, e.g. `{'rpm': true, 'lean_deg':
  /// false}`. This is a **denylist**, matching upstream semantics exactly:
  /// a field explicitly marked `false` is always forced to null in the
  /// parsed output, even if the byte-level 0x40 gate would have computed a
  /// value. A field marked `true`, or simply absent from this map, is
  /// parsed opportunistically from whatever the 0x40 gate (or the live
  /// per-connection info-config frame) allows.
  final Map<String, bool> supportedFields;

  /// Raw 0x40 flag values observed for this model, used to gate 0x41/0x45
  /// fields before the bike has sent its own live 0x40 frame.
  final Map<String, int> infoConfigFlags;

  const BikeConfig({
    required this.model,
    required this.startupFrames,
    this.startupNoWaitFrames = const {},
    this.controlWriteWithResponse = true,
    this.requireStartupResponses = true,
    this.startupWaitTimeout = const Duration(seconds: 3),
    this.startupInterFrameDelay = const Duration(milliseconds: 200),
    this.startupRetries = 3,
    this.startupRetryDelay = const Duration(seconds: 1),
    this.rpmMode = 'auto',
    this.wheelMode = 'auto',
    this.supportedFields = const <String, bool>{},
    this.infoConfigFlags = const {},
  });
}
