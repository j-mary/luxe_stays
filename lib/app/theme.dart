import 'package:flutter/material.dart';

/// A restrained, "quiet luxury" theme.
///
/// Deep green and warm brass rather than the saturated blue every booking app
/// defaults to. Generous type sizes and high contrast, because the primary
/// audience skews older and often books on a phone in bright daylight.
abstract final class AppTheme {
  static const Color _brandGreen = Color(0xFF14342B);
  static const Color _brass = Color(0xFFB08D57);

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: _brandGreen,
      brightness: brightness,
      secondary: _brass,
    );

    // Deliberately narrow. `appBarTheme` and `inputDecorationTheme` are omitted
    // because their data-class types changed in the Flutter 3.32 theme migration
    // (`AppBarTheme` -> `AppBarThemeData`, `InputDecorationTheme` ->
    // `InputDecorationThemeData`), so hard-coding either name pins the project to
    // one side of that boundary. The seeded `ColorScheme` already gives the app
    // bar the right colours, and every input in this app passes its own
    // `OutlineInputBorder`. Add them back once the team pins an SDK version.
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFFAF8F5)
          : scheme.surface,
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      // A height floor, NOT `Size.fromHeight`. `Size.fromHeight(50)` is
      // `Size(double.infinity, 50)`, which makes every button in the app demand
      // infinite width. That is invisible inside a ListView (the cross axis is
      // already bounded) and throws "BoxConstraints forces an infinite width"
      // the moment a button appears inside a Row. Buttons that should span the
      // screen say so at the call site with a SizedBox.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
