import 'package:flutter/widgets.dart';

/// Phosphor icon glyphs, referenced directly by codepoint/font family
/// instead of through `package:phosphor_flutter`'s Dart API.
///
/// `phosphor_flutter` 2.1.0 (pub.dev's latest, as of this writing) defines
/// its icon-data classes as `class PhosphorIconData extends IconData`,
/// which no longer compiles against this Flutter SDK — `IconData` was
/// made a `final` class, and final classes can't be extended outside
/// their own library. The package is still a `pubspec.yaml` dependency
/// purely so its bundled font files (`lib/fonts/Phosphor*.ttf`, declared
/// in the package's own `flutter: fonts:` section) get included in the
/// build — Flutter does that automatically for any dependency, no import
/// of the package's Dart code required. These constants point at the
/// same codepoints in the same fonts; use `Icon(Ph.xxx, ...)`, not
/// `PhosphorIcon`.
abstract final class Ph {
  static const _regular = 'PhosphorRegular';
  static const _fill = 'PhosphorFill';
  static const _pkg = 'phosphor_flutter';

  static const IconData path = IconData(0xe39c, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData ranking = IconData(0xed62, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData hexagon = IconData(0xe2ae, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData motorcycle = IconData(0xe80a, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData car = IconData(0xe112, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData users = IconData(0xe4d6, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData magnifyingGlass = IconData(0xe30c, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData arrowLeft = IconData(0xe058, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData caretLeft = IconData(0xe138, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData caretRight = IconData(0xe13a, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData export_ = IconData(0xeaf0, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData trash = IconData(0xe4a6, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData pencilSimple = IconData(0xe3b4, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData gearSix = IconData(0xe272, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData crosshair = IconData(0xe1d6, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData globeHemisphereWest = IconData(0xe28c, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData cloudArrowUp = IconData(0xe1ae, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData signOut = IconData(0xe42a, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData calendarBlank = IconData(0xe10a, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData flagCheckered = IconData(0xea38, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData moonStars = IconData(0xe58e, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData dotsThree = IconData(0xe1fe, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData plus = IconData(0xe3d4, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData musicNote = IconData(0xe33c, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData googleLogo = IconData(0xe292, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData envelopeSimple = IconData(0xe218, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData userCircle = IconData(0xe4c4, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData fileText = IconData(0xe23a, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData downloadSimple = IconData(0xe20c, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData x = IconData(0xe4f6, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData pause = IconData(0xe39e, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData bluetooth = IconData(0xe0da, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData repeat = IconData(0xe3f6, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData arrowsClockwise = IconData(0xe094, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData gauge = IconData(0xe628, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData compass = IconData(0xe1c8, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);
  static const IconData mapTrifold = IconData(0xe31a, fontFamily: _regular, fontPackage: _pkg, matchTextDirection: true);

  /// Fill weight — used only for the now-playing music note and the
  /// replay play glyph, per the design handoff.
  static const IconData musicNoteFill = IconData(0xe33c, fontFamily: _fill, fontPackage: _pkg, matchTextDirection: true);
  static const IconData playFill = IconData(0xe3d0, fontFamily: _fill, fontPackage: _pkg, matchTextDirection: true);
  static const IconData pauseFill = IconData(0xe39e, fontFamily: _fill, fontPackage: _pkg, matchTextDirection: true);
}
