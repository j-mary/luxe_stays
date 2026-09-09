import 'package:flutter/material.dart';

/// A hairline-bordered block on the paper — this app's replacement for [Card].
///
/// Material's card is a rounded, elevated, tinted surface. Three properties,
/// all of which pull against a print register: the radius reads as software,
/// the elevation puts a shadow where the design wants a rule, and the surface
/// tint washes the container in the seed hue. `AppPanel` keeps the grouping and
/// drops all three.
///
/// It is a widget rather than a `cardTheme` entry on purpose. The theme data
/// classes for cards, app bars and input decoration were re-typed in the
/// Flutter 3.32 theme migration, so setting them pins the project to one side
/// of that change; composing a widget does not.
class AppPanel extends StatelessWidget {
  const AppPanel({
    required this.child,
    this.margin = EdgeInsets.zero,
    this.color,
    this.clipBehavior = Clip.antiAlias,
    super.key,
  });

  final Widget child;

  /// Outer spacing, matching [Card.margin] so call sites read the same.
  final EdgeInsetsGeometry margin;

  /// Defaults to the surface colour. Set it for the error and emphasis panels.
  final Color? color;

  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: margin,
      child: Container(
        clipBehavior: clipBehavior,
        decoration: BoxDecoration(
          color: color ?? colors.surface,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: child,
      ),
    );
  }
}
