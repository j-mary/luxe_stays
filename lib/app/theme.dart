import 'package:flutter/material.dart';

/// The visual system: warm ivory paper, antique gold, and a serif voice.
///
/// Three rules hold it together.
///
/// **Gold is the accent, charcoal-gold is the action.** A true gold cannot
/// carry white text at body size, so the filled-button colour is a deepened
/// antique gold that clears 4.5:1 against white, and the brighter gold is spent
/// on marks, rules and overlines where contrast requirements are lighter.
///
/// **Serif for voice, sans for work.** Display sizes, section headings and
/// property names are set in a serif; body copy, labels and anything dense
/// stays in the platform sans, which is what keeps a price list legible at
/// 12.5px. The serif is resolved from fonts already on the device — no bundled
/// binary, no runtime download — so the exact face differs slightly between
/// iOS and Android by design.
///
/// **Corners are nearly square.** 2px on controls, none on imagery. Rounded
/// cards read as software; sharp edges and a hairline rule read as print, which
/// is the register this product is trying to occupy.
abstract final class AppTheme {
  // --- Type ---------------------------------------------------------------
  /// Georgia exists on iOS and macOS; Android resolves through the fallback
  /// chain to Noto Serif. Neither platform downloads anything.
  static const String _serif = 'Georgia';
  static const List<String> _serifFallback = <String>[
    'Times New Roman',
    'Noto Serif',
    'serif',
  ];

  // --- Light palette ------------------------------------------------------
  /// Warm near-black. A brown cast rather than a blue one, so it sits with the
  /// gold instead of fighting it.
  static const Color _ink = Color(0xFF1A1712);
  static const Color _inkMuted = Color(0xFF6B635A);
  static const Color _inkFaint = Color(0xFF9A9187);

  /// The action colour. Deep enough for white text at body size (~4.9:1).
  static const Color _goldDeep = Color(0xFF8C6A32);

  /// The accent colour: marks, rules, overlines, membership cues.
  static const Color _gold = Color(0xFFA9853F);

  static const Color _paper = Color(0xFFFCFAF6);
  static const Color _card = Color(0xFFFFFFFF);
  static const Color _hairline = Color(0xFFE8E1D5);
  static const Color _subtle = Color(0xFFF4F0E8);
  static const Color _danger = Color(0xFF8C2F22);

  // --- Dark palette -------------------------------------------------------
  static const Color _darkPaper = Color(0xFF14120F);
  static const Color _darkCard = Color(0xFF1B1815);
  static const Color _darkHairline = Color(0xFF302B24);
  static const Color _darkSubtle = Color(0xFF231F1A);
  static const Color _darkInk = Color(0xFFF0EBE2);
  static const Color _darkInkMuted = Color(0xFFA39A8D);
  static const Color _goldLight = Color(0xFFC6A063);

  /// Ink plate used where the design is deliberately emphatic — the membership
  /// panel, image scrims. Shared so those surfaces stay in step.
  static const Color plate = Color(0xFF191510);
  static const Color onPlate = Color(0xFFF5F1E8);
  static const Color plateGold = _goldLight;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  /// A serif [TextStyle] for headings, with the platform fallback chain
  /// attached. Exposed so a screen can set an occasional oversized serif
  /// without re-deriving the family.
  static TextStyle serif({
    required double size,
    Color? color,
    FontWeight weight = FontWeight.w400,
    double letterSpacing = -0.2,
    double height = 1.2,
  }) {
    return TextStyle(
      fontFamily: _serif,
      fontFamilyFallback: _serifFallback,
      fontSize: size,
      color: color,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static ThemeData _build(Brightness brightness) {
    final bool isLight = brightness == Brightness.light;

    final ColorScheme scheme =
        ColorScheme.fromSeed(seedColor: _goldDeep, brightness: brightness)
            .copyWith(
      primary: isLight ? _goldDeep : _goldLight,
      onPrimary: isLight ? Colors.white : const Color(0xFF241A0B),
      secondary: isLight ? _gold : _goldLight,
      onSecondary: Colors.white,
      surface: isLight ? _card : _darkCard,
      onSurface: isLight ? _ink : _darkInk,
      onSurfaceVariant: isLight ? _inkMuted : _darkInkMuted,
      outline: isLight ? _inkFaint : const Color(0xFF544C42),
      outlineVariant: isLight ? _hairline : _darkHairline,
      error: _danger,
      onError: Colors.white,
      // Neutral containers. A tinted container is the wash this theme exists to
      // avoid; emphasis comes from a rule, a weight or the ink plate.
      primaryContainer: isLight ? _subtle : _darkSubtle,
      onPrimaryContainer: isLight ? _ink : _darkInk,
      secondaryContainer: isLight ? _subtle : _darkSubtle,
      onSecondaryContainer: isLight ? _ink : _darkInk,
      surfaceContainerHighest: isLight ? _subtle : _darkSubtle,
      errorContainer:
          isLight ? const Color(0xFFF7E8E4) : const Color(0xFF2E1714),
      onErrorContainer:
          isLight ? const Color(0xFF5C1E15) : const Color(0xFFF0C8C1),
      // Removes Material 3's elevation tint, which would otherwise put a gold
      // wash over any scrolled-under app bar.
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
      textTheme: _textTheme(scheme),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 54),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
          // Sans, slightly tracked: the action reads as a stamp rather than a
          // sentence, which is what stops it competing with the serif above it.
          // Tracking stays modest because most labels here are words rather
          // than single verbs, and wide tracking on a phrase reads as shouting.
          textStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 46),
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline.withAlpha(110)),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
          textStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        side: BorderSide(color: scheme.outlineVariant),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
        ),
        labelStyle: TextStyle(
          fontSize: 12,
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.secondary,
        linearMinHeight: 2,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight ? plate : _darkSubtle,
        contentTextStyle: TextStyle(
          color: isLight ? onPlate : _darkInk,
          fontSize: 13.5,
        ),
        actionTextColor: _goldLight,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
        ),
      ),
    );
  }

  /// Serif above, sans below. The break sits at `titleSmall`: everything larger
  /// carries the brand's voice, everything smaller has a job to do.
  static TextTheme _textTheme(ColorScheme scheme) {
    final Color ink = scheme.onSurface;
    final Color muted = scheme.onSurfaceVariant;

    return TextTheme(
      displaySmall: serif(
        size: 38,
        color: ink,
        letterSpacing: -0.6,
        height: 1.08,
      ),
      headlineMedium: serif(
        size: 29,
        color: ink,
        letterSpacing: -0.4,
        height: 1.14,
      ),
      headlineSmall: serif(
        size: 23,
        color: ink,
        letterSpacing: -0.3,
        height: 1.2,
      ),
      titleLarge: serif(
        size: 20,
        color: ink,
        letterSpacing: -0.2,
        height: 1.25,
      ),
      titleMedium: serif(
        size: 17.5,
        color: ink,
        letterSpacing: -0.1,
        height: 1.3,
      ),

      // --- sans, from here down ---
      titleSmall: TextStyle(
        fontSize: 13.5,
        height: 1.3,
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.55, color: ink),
      bodyMedium: TextStyle(fontSize: 13.5, height: 1.55, color: ink),
      bodySmall: TextStyle(fontSize: 12.5, height: 1.5, color: muted),
      labelLarge: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: ink,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: muted,
      ),
      // The overline, used uppercase at the call site. Wide tracking is most
      // of what makes a small label read as editorial rather than as UI chrome.
      labelSmall: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: muted,
      ),
    );
  }
}
