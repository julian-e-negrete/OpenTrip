import 'package:flutter/material.dart';

/// OpenTrip's "Bold & Energetic" visual identity: vibrant coral/violet/lime
/// accents on a warm-black (dark) or warm-white (light) ground, heavier
/// type at a bigger scale than stock Material. Chosen by comparing three
/// mocked-up directions (automotive-dashboard, refined-minimal, this one)
/// side by side — see docs/ROADMAP.md.
///
/// The three accent roles map onto specific stats everywhere they're shown
/// (recording_screen.dart, trip_detail_screen.dart) rather than being
/// interchangeable Material roles:
///   - [ColorScheme.primary]   (coral)  — speed, the record button, the
///     active bottom-nav tab.
///   - [ColorScheme.secondary] (violet) — distance, the route line on the
///     map, BLE/bike telemetry.
///   - [ColorScheme.tertiary]  (lime)   — lean angle, anything about
///     cornering/grip.
/// [ColorScheme.error] is a separate, more purely-red hue from primary's
/// coral-pink on purpose — a delete/error action needs to read as distinct
/// from routine "this is the brand accent" coral.
class AppTheme {
  AppTheme._();

  static const _lightBg = Color(0xFFFFF4EC);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightInk = Color(0xFF1A1025);
  static const _lightMuted = Color(0xFF7A6E82);
  static const _lightBorder = Color(0xFFF0DCCB);
  static const _lightCoral = Color(0xFFD1225A);
  static const _lightViolet = Color(0xFF5B32D6);
  static const _lightLime = Color(0xFF1C8F57);
  static const _lightError = Color(0xFFBA1A1A);

  static const _darkBg = Color(0xFF1A1025);
  static const _darkSurface = Color(0xFF251731);
  static const _darkInk = Color(0xFFF5EFFF);
  static const _darkMuted = Color(0xFFA99BB8);
  static const _darkBorder = Color(0xFF33223F);
  static const _darkCoral = Color(0xFFFF4D6D);
  static const _darkViolet = Color(0xFF9C6BFF);
  static const _darkLime = Color(0xFFC6FF3D);
  static const _darkError = Color(0xFFFFB4AB);

  static final ThemeData light = _build(
    brightness: Brightness.light,
    bg: _lightBg,
    surface: _lightSurface,
    ink: _lightInk,
    muted: _lightMuted,
    border: _lightBorder,
    coral: _lightCoral,
    violet: _lightViolet,
    lime: _lightLime,
    error: _lightError,
  );

  static final ThemeData dark = _build(
    brightness: Brightness.dark,
    bg: _darkBg,
    surface: _darkSurface,
    ink: _darkInk,
    muted: _darkMuted,
    border: _darkBorder,
    coral: _darkCoral,
    violet: _darkViolet,
    lime: _darkLime,
    error: _darkError,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color ink,
    required Color muted,
    required Color border,
    required Color coral,
    required Color violet,
    required Color lime,
    required Color error,
  }) {
    final isDark = brightness == Brightness.dark;
    final onCoral = isDark ? _darkBg : Colors.white;
    final onLime = isDark ? _darkBg : Colors.white;
    final onError = isDark ? _darkBg : Colors.white;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: coral,
      onPrimary: onCoral,
      secondary: violet,
      onSecondary: Colors.white,
      tertiary: lime,
      onTertiary: onLime,
      error: error,
      onError: onError,
      surface: surface,
      onSurface: ink,
      surfaceContainerHighest: border,
      onSurfaceVariant: muted,
      outline: border,
      outlineVariant: border,
      inverseSurface: ink,
      onInverseSurface: surface,
    );

    final textTheme = Typography.material2021(platform: TargetPlatform.android).black.apply(
      bodyColor: ink,
      displayColor: ink,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      splashFactory: InkSparkle.splashFactory,
      textTheme: textTheme.copyWith(
        titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
        titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        bodyMedium: textTheme.bodyMedium?.copyWith(color: ink),
        bodySmall: textTheme.bodySmall?.copyWith(color: muted),
        labelLarge: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        labelSmall: textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: muted,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: border),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: ink,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: border.withValues(alpha: isDark ? 0.35 : 0.6),
        labelStyle: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 12),
        side: BorderSide(color: border),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 24),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: coral, width: 2),
        ),
        labelStyle: TextStyle(color: muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: coral,
          foregroundColor: onCoral,
          textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.1),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: border),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: coral,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? coral : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(onCoral),
        side: BorderSide(color: muted, width: 1.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? coral : muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? coral.withValues(alpha: 0.35) : border,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: coral.withValues(alpha: isDark ? 0.22 : 0.14),
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: states.contains(WidgetState.selected) ? coral : muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? coral : muted,
            size: 24,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: TextStyle(color: surface, fontWeight: FontWeight.w600),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w800),
        contentTextStyle: TextStyle(color: muted, fontSize: 14),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: coral),
      iconTheme: IconThemeData(color: ink),
    );
  }
}
