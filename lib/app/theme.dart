import 'package:flutter/material.dart';

/// The visual system.
///
/// Two decisions shape everything below, and both are corrections of what
/// `ColorScheme.fromSeed` gives you by default.
///
/// **Surfaces are neutral, not tinted.** A seeded Material 3 scheme derives
/// `primaryContainer`, `surfaceContainerHighest` and the elevation overlay from
/// the seed hue, so every card, banner and app bar ends up washed in a pale
/// version of the brand colour. It reads as unfinished. Here the surfaces are
/// warm neutrals separated by hairline borders, and the accent is spent only
/// where it means something: the primary action, and marks of membership.
///
/// **Hierarchy comes from type and space, not from colour and elevation.**
/// There are no shadows. Weight, size, letter-spacing and generous whitespace
/// do the work, which is how the print-derived typography of the hospitality
/// brands this app sits alongside actually behaves.
abstract final class AppTheme {
  // --- Light palette ------------------------------------------------------
  /// Near-black with a faint green cast, so body copy sits in the same family
  /// as the accent without ever competing with it.
  static const Color _ink = Color(0xFF14201B);
  static const Color _inkMuted = Color(0xFF5E6A64);
  static const Color _inkFaint = Color(0xFF8B948E);

  /// The accent. Deep enough to carry white text at any size.
  static const Color _forest = Color(0xFF0E3B2E);

  /// Reserved for membership and premium cues - never for ordinary chrome.
  static const Color _brass = Color(0xFF9A7B4F);

  static const Color _paper = Color(0xFFFBFAF7);
  static const Color _card = Color(0xFFFFFFFF);
  static const Color _hairline = Color(0xFFE5E1D9);
  static const Color _subtle = Color(0xFFF2F0EA);
  static const Color _danger = Color(0xFF8C2F22);

  // --- Dark palette -------------------------------------------------------
  static const Color _darkPaper = Color(0xFF10120F);
  static const Color _darkCard = Color(0xFF181B17);
  static const Color _darkHairline = Color(0xFF2C302B);
  static const Color _darkSubtle = Color(0xFF20241F);
  static const Color _darkInk = Color(0xFFECEFE9);
  static const Color _darkInkMuted = Color(0xFF9AA39C);
  static const Color _sage = Color(0xFF7FB79E);
  static const Color _brassDark = Color(0xFFC9A876);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isLight = brightness == Brightness.light;

    final ColorScheme scheme =
        ColorScheme.fromSeed(seedColor: _forest, brightness: brightness)
            .copyWith(
      primary: isLight ? _forest : _sage,
      onPrimary: isLight ? Colors.white : const Color(0xFF06231A),
      secondary: isLight ? _brass : _brassDark,
      onSecondary: Colors.white,
      surface: isLight ? _card : _darkCard,
      onSurface: isLight ? _ink : _darkInk,
      onSurfaceVariant: isLight ? _inkMuted : _darkInkMuted,
      outline: isLight ? _inkFaint : const Color(0xFF4A514B),
      outlineVariant: isLight ? _hairline : _darkHairline,
      error: _danger,
      onError: Colors.white,
      // Containers are neutral on purpose: a tinted container is exactly the
      // wash this theme exists to avoid. Widgets that want emphasis use a
      // border and type weight instead.
      primaryContainer: isLight ? _subtle : _darkSubtle,
      onPrimaryContainer: isLight ? _ink : _darkInk,
      secondaryContainer: isLight ? _subtle : _darkSubtle,
      onSecondaryContainer: isLight ? _ink : _darkInk,
      surfaceContainerHighest: isLight ? _subtle : _darkSubtle,
      errorContainer: isLight ? const Color(0xFFF6E7E4) : const Color(0xFF2E1714),
      onErrorContainer: isLight ? const Color(0xFF5C1E15) : const Color(0xFFF0C8C1),
      // Kills Material 3's elevation tint overlay, which is what turns a
      // scrolled-under app bar the colour of the seed.
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isLight ? _paper : _darkPaper,
      canvasColor: isLight ? _paper : _darkPaper,
      dividerColor: scheme.outlineVariant,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
      textTheme: _textTheme(scheme),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      // Restrained corner radii. Anything above ~12 starts to read as a toy.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outlineVariant),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        side: BorderSide(color: scheme.outlineVariant),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
        labelStyle: TextStyle(
          fontSize: 12.5,
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearMinHeight: 2,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight ? _ink : _darkSubtle,
        contentTextStyle: TextStyle(
          color: isLight ? Colors.white : _darkInk,
          fontSize: 14,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
    );
  }

  /// Tight, high-contrast display sizes; quiet, roomy body copy.
  ///
  /// Negative letter-spacing on the large sizes and positive spacing on the
  /// small uppercase labels is most of what separates a considered type scale
  /// from the framework default.
  static TextTheme _textTheme(ColorScheme scheme) {
    final Color ink = scheme.onSurface;
    final Color muted = scheme.onSurfaceVariant;

    return TextTheme(
      displaySmall: TextStyle(
        fontSize: 34,
        height: 1.1,
        letterSpacing: -1.0,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 27,
        height: 1.15,
        letterSpacing: -0.7,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        height: 1.2,
        letterSpacing: -0.5,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        height: 1.25,
        letterSpacing: -0.3,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 15.5,
        height: 1.3,
        letterSpacing: -0.15,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        height: 1.3,
        letterSpacing: -0.1,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 15.5, height: 1.5, color: ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: ink),
      bodySmall: TextStyle(fontSize: 13, height: 1.45, color: muted),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: ink,
      ),
      labelMedium: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: muted,
      ),
      // The overline: small, spaced, uppercase at the call site.
      labelSmall: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.9,
        color: muted,
      ),
    );
  }
}
