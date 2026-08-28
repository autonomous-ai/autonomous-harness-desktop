import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;

/// Shared terminal-shell palette.
///
/// ⚠️ THESE ARE NOW ADAPTERS, NOT VALUES, AND THAT IS THE POINT. Every one of
/// them used to be a `const` slate colour, which is why nine files could read
/// this palette and still paint a dark window while the rest of the app went
/// light: a constant cannot answer "which theme is it".
///
/// Each name below resolves through [grid.AppPalette], the design system that
/// already carries a light and a dark value for every role — and carries the
/// contrast ratio it was chosen for, in a comment, next to it. Mapping onto it
/// rather than inventing a second light palette is deliberate: two palettes for
/// one app do not stay in agreement, and the one that drifts is always the one
/// nobody is looking at.
///
/// The DARK values are unchanged in spirit but no longer identical — they are
/// now whatever the design system says dark is, so the two halves of the app
/// stop disagreeing by a few points of grey along the seam between them.
///
/// Being getters, they cannot appear in a `const` expression. That is a feature:
/// the compiler names every site that froze a colour at build time, which is
/// exactly the set of places light mode would otherwise have missed.
abstract final class AppColors {
  /// The window itself.
  static Color get background => grid.AppPalette.windowBg;

  /// The rail column, set apart from [background] by a hairline rather than a tone.
  static Color get sidebar => grid.AppPalette.panelBg;

  /// Quiet cards and input fills.
  static Color get surface => grid.AppPalette.cardBg;
  static Color get hover => grid.AppPalette.cardBgHover;
  static Color get selected => grid.AppSurface.selectedFill;

  /// A hairline between blocks, and the stronger one that has to hold a shape.
  static Color get border => grid.AppPalette.divider;
  static Color get borderStrong => grid.AppPalette.guide;

  /// Ink, in three weights.
  static Color get text => grid.AppPalette.textPrimary;
  static Color get textSoft => grid.AppPalette.textSecondary;
  static Color get muted => grid.AppPalette.textFaint;
  static Color get mutedStrong => grid.AppPalette.textSecondary;

  /// The accent as a MARK on a surface, not as a fill behind white text — which
  /// is what these call sites use it for (an icon, a link, a focused rim).
  static Color get accent => grid.AppPalette.accentOnSurface;

  static Color get success => grid.AppPalette.online;
  static Color get warning => grid.AppPalette.warn;

  /// Error ink on a surface. NOT [grid.AppPalette.dangerFill], which is tuned to
  /// carry white lettering on top of it and is far too dark to read AS text.
  static Color get danger =>
      grid.AppTheme.pick(const Color(0xFFB3261E), const Color(0xFFF2544B));
}

/// The app's two font stacks. Mono is for strings the user copies (a token, a
/// path, terminal output) — everything else is read, not copied, and reads
/// faster in the system's own UI face. `.AppleSystemUIFont` is the private
/// CoreText name that actually resolves to San Francisco on macOS; the public
/// name `'SF Pro'`/`'SF Mono'` does not resolve and silently falls through to
/// Menlo instead, which is the trap this constant avoids.
abstract final class AppFonts {
  static const String sans = '.AppleSystemUIFont';
  static const List<String> sansFallback = [
    'SF Pro Text',
    'Helvetica Neue',
    'Arial',
  ];
  static const String mono = 'Menlo';
}

abstract final class AppTheme {
  /// The dark shell, kept as a name because call sites and tests use it.
  static ThemeData get terminalDark => terminal(Brightness.dark);

  /// The light shell — the same chrome, resolved against the light palette.
  static ThemeData get terminalLight => terminal(Brightness.light);

  /// Build the shell for [b].
  ///
  /// ⚠️ WRAPPED IN `grid.AppTheme.as`, AND IT HAS TO BE. Every colour below now
  /// reads through [AppColors], which resolves against ONE global brightness —
  /// the same global that makes `AppPalette.windowBg` follow the theme with no
  /// plumbing at any call site. MaterialApp asks for both themes up front, long
  /// before that global has been told which one is being worn, so building them
  /// straight would hand back two copies of whatever the app happened to be
  /// wearing at startup. `as` swaps the global, reads, and puts it back.
  static ThemeData terminal(Brightness b) =>
      grid.AppTheme.as(b, () => _terminal(b));

  static ThemeData _terminal(Brightness b) {
    final scheme = ColorScheme(
      brightness: b,
      primary: AppColors.accent,
      onPrimary: AppColors.background,
      secondary: AppColors.success,
      onSecondary: AppColors.background,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      error: AppColors.danger,
      onError: AppColors.background,
      outline: AppColors.border,
    );
    final sansBase = TextStyle(
      fontFamily: AppFonts.sans,
      fontFamilyFallback: AppFonts.sansFallback,
      color: AppColors.text,
    );
    return ThemeData(
      brightness: b,
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      fontFamily: AppFonts.sans,
      fontFamilyFallback: AppFonts.sansFallback,
      splashFactory: NoSplash.splashFactory,
      textTheme: TextTheme(
        headlineSmall: sansBase,
        titleLarge: sansBase,
        titleMedium: sansBase,
        titleSmall: sansBase,
        bodyLarge: sansBase,
        bodyMedium: sansBase,
        bodySmall: sansBase.copyWith(color: AppColors.mutedStrong),
        labelLarge: sansBase,
        labelMedium: sansBase,
        labelSmall: sansBase.copyWith(color: AppColors.muted),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: AppColors.mutedStrong, size: 18),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        isDense: true,
        hintStyle: TextStyle(
          color: AppColors.muted,
          fontFamily: AppFonts.sans,
          fontFamilyFallback: AppFonts.sansFallback,
          fontSize: 12,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: BorderSide(color: AppColors.accent),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: AppColors.borderStrong),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.borderStrong),
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: TextStyle(
          color: AppColors.textSoft,
          fontFamily: AppFonts.sans,
          fontFamilyFallback: AppFonts.sansFallback,
          fontSize: 11,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSoft,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.background,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.border,
      ),
    );
  }
}
