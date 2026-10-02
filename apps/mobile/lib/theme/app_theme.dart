// OpenTrip — Nocturne theme
// Drop-in replacement for apps/mobile/lib/theme/app_theme.dart.
// Every value here comes from the Nocturne token sheet
// (_ds/nocturne-.../styles.css). Do not introduce colours outside this file.
//
// Requires in pubspec.yaml:
//   google_fonts: ^6.1.0
// (or vendor Inter under assets/fonts and set fontFamily: 'Inter')

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Raw Nocturne tokens. Reference these directly for anything ThemeData
/// cannot express (stat labels, gauge strokes, map overlays).
abstract final class Noct {
  // Core roles
  static const bg = Color(0xFF161826);
  static const surface = Color(0xFF232532);
  static const text = Color(0xFFE9E9ED);
  static const accent = Color(0xFF9184D9);
  static const divider = Color(0x29E9E9ED); // #e9e9ed @ 16%

  // Neutral ramp
  static const n100 = Color(0xFFF3F5FE);
  static const n200 = Color(0xFFE4E7F5);
  static const n300 = Color(0xFFCFD3E5);
  static const n400 = Color(0xFFB2B6CA);
  static const n500 = Color(0xFF9397AB);
  static const n600 = Color(0xFF75798C);
  static const n700 = Color(0xFF595D6C);
  static const n800 = Color(0xFF3F424D);
  static const n900 = Color(0xFF292B31);

  // Accent ramp
  static const a100 = Color(0xFFF5F4FF);
  static const a200 = Color(0xFFE7E5FE);
  static const a300 = Color(0xFFD2CEFD);
  static const a400 = Color(0xFFB5ABFC);
  static const a500 = Color(0xFF968AE0);
  static const a600 = Color(0xFF796CBF);
  static const a700 = Color(0xFF5D5294);
  static const a800 = Color(0xFF423A6A);
  static const a900 = Color(0xFF2B2741);

  /// Map / media canvas — one step below the page ground.
  static const canvas = Color(0xFF10121C);

  /// Share-card ground (the only saturated fill in the app).
  static const section = Color(0xFF262A60);

  // Spacing scale (density 0.70x). Round to these, not to 8-pt.
  static const s1 = 2.8, s2 = 5.6, s3 = 8.4, s4 = 11.2, s6 = 16.8, s8 = 22.4;

  // Radii
  static const rSm = 4.0, rMd = 8.0, rLg = 14.0;

  /// Elevation is a hairline edge, never a drop shadow, at rest.
  static const shadowSm = <BoxShadow>[];
  static Border get edgeSm => Border.all(color: n800, width: 1);
  static const shadowMd = <BoxShadow>[
    BoxShadow(color: Color(0x8C000000), blurRadius: 18, offset: Offset(0, 6)),
  ];

  /// Standard surface panel: flat fill + hairline edge, 8px radius.
  static BoxDecoration get panel => BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(rMd),
        border: Border.all(color: n800, width: 1),
      );

  /// "Yours / live" panel — the only tinted surface.
  static BoxDecoration get panelAccent => BoxDecoration(
        color: a900,
        borderRadius: BorderRadius.circular(rMd),
        border: Border.all(color: a700, width: 1),
      );

  /// The uppercase micro-label under every statistic.
  static const statLabel = TextStyle(
    fontSize: 9.5,
    height: 1.2,
    letterSpacing: 1.05, // ~.11em
    fontWeight: FontWeight.w400,
    color: n500,
  );

  /// Big numerals. Always tabular, always w500, never bold.
  static TextStyle stat(double size, {Color? color}) => TextStyle(
        fontSize: size,
        height: 0.9,
        letterSpacing: size * -0.03,
        fontWeight: FontWeight.w500,
        color: color ?? text,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

abstract final class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final scheme = const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: Noct.accent,
      onPrimary: Noct.a100,
      primaryContainer: Noct.a900,
      onPrimaryContainer: Noct.a200,
      secondary: Noct.accent,
      onSecondary: Noct.a100,
      secondaryContainer: Noct.a900,
      onSecondaryContainer: Noct.a200,
      surface: Noct.bg,
      onSurface: Noct.text,
      surfaceContainerLowest: Noct.canvas,
      surfaceContainerLow: Noct.bg,
      surfaceContainer: Noct.surface,
      surfaceContainerHigh: Noct.surface,
      surfaceContainerHighest: Noct.surface,
      onSurfaceVariant: Noct.n500,
      outline: Noct.n800,
      outlineVariant: Noct.n900,
      error: Color(0xFFE8899B),
      onError: Color(0xFF2B1A1F),
    );

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: Noct.text,
      displayColor: Noct.text,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: Noct.bg,
      canvasColor: Noct.bg,
      dividerColor: Noct.n900,
      splashFactory: InkRipple.splashFactory,
      // Hierarchy is size and space — nothing is heavier than w500.
      textTheme: textTheme.copyWith(
        displayLarge: textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w500, letterSpacing: -2.4, height: 0.88),
        displayMedium: textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w500, letterSpacing: -1.8, height: 0.9),
        headlineLarge: textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w500, letterSpacing: -0.9),
        headlineMedium: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w500, letterSpacing: -0.7),
        titleLarge: textTheme.titleLarge?.copyWith(fontSize: 26, fontWeight: FontWeight.w500, letterSpacing: -0.52),
        titleMedium: textTheme.titleMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: 0),
        bodyLarge: textTheme.bodyLarge?.copyWith(fontSize: 13.5, height: 1.5),
        bodyMedium: textTheme.bodyMedium?.copyWith(fontSize: 12.5, height: 1.55, color: Noct.n400),
        bodySmall: textTheme.bodySmall?.copyWith(fontSize: 11, height: 1.45, color: Noct.n500),
        labelSmall: Noct.statLabel,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Noct.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Noct.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 18,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: const IconThemeData(color: Noct.n400, size: 19),
        actionsIconTheme: const IconThemeData(color: Noct.n400, size: 19),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 26, fontWeight: FontWeight.w500, letterSpacing: -0.52, color: Noct.text,
        ),
      ),
      // Flat surface + hairline edge. No Material elevation anywhere.
      cardTheme: CardThemeData(
        color: Noct.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Noct.rMd),
          side: const BorderSide(color: Noct.n800, width: 1),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        minVerticalPadding: 13,
        iconColor: Noct.n500,
        textColor: Noct.text,
        titleTextStyle: TextStyle(fontSize: 13.5, color: Noct.text),
        subtitleTextStyle: TextStyle(fontSize: 11, color: Noct.n500),
      ),
      dividerTheme: const DividerThemeData(color: Noct.n900, thickness: 1, space: 1),
      // Primary actions are OUTLINED, never filled.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(Noct.a200),
          side: const WidgetStatePropertyAll(BorderSide(color: Noct.accent, width: 1.5)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18, vertical: 15)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Noct.rMd)),
          ),
          textStyle: WidgetStatePropertyAll(
            GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w500),
          ),
          overlayColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.pressed)) return Noct.a800.withValues(alpha: 0.55);
            if (s.contains(WidgetState.hovered)) return Noct.accent.withValues(alpha: 0.14);
            return null;
          }),
        ),
      ),
      // Secondary: neutral outline.
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(Noct.n300),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Noct.rMd)),
          ),
          textStyle: WidgetStatePropertyAll(GoogleFonts.inter(fontSize: 13)),
          overlayColor: WidgetStatePropertyAll(Noct.n100.withValues(alpha: 0.05)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          iconColor: const WidgetStatePropertyAll(Noct.n400),
          iconSize: const WidgetStatePropertyAll(19),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Noct.rMd)),
          ),
          overlayColor: WidgetStatePropertyAll(Noct.n100.withValues(alpha: 0.05)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: Noct.a900,
        side: const BorderSide(color: Noct.divider),
        labelStyle: GoogleFonts.inter(fontSize: 12, color: Noct.n400),
        secondaryLabelStyle: GoogleFonts.inter(fontSize: 12, color: Noct.a100),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Noct.rMd)),
        showCheckmark: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Noct.surface,
        hintStyle: GoogleFonts.inter(fontSize: 13, color: Noct.n500),
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Noct.rMd),
          borderSide: const BorderSide(color: Noct.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Noct.rMd),
          borderSide: const BorderSide(color: Noct.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Noct.rMd),
          borderSide: const BorderSide(color: Noct.accent, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Noct.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent, // no Material pill
        elevation: 0,
        height: 62,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 20,
            color: s.contains(WidgetState.selected) ? Noct.accent : Noct.n500,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => GoogleFonts.inter(
            fontSize: 10,
            color: s.contains(WidgetState.selected) ? Noct.accent : Noct.n500,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Noct.a200 : Noct.n600,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Noct.a800 : Noct.n900,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: Noct.accent,
        inactiveTrackColor: Noct.n800,
        thumbColor: Noct.a200,
        trackHeight: 3,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Noct.accent,
        linearTrackColor: Noct.n900,
        linearMinHeight: 6,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Noct.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Noct.rLg)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Noct.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Noct.rLg),
          side: const BorderSide(color: Noct.n700, width: 1),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Noct.surface,
        contentTextStyle: GoogleFonts.inter(fontSize: 13, color: Noct.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Noct.rMd)),
      ),
    );
  }
}
