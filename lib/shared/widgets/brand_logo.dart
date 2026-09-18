import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// The compact LuxeStays monogram and wordmark used in application chrome.
///
/// The image is also the source artwork for the Android and iOS launcher
/// icons, keeping the installed app and its masthead visually consistent.
class LuxeStaysLogo extends StatelessWidget {
  const LuxeStaysLogo({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Semantics(
      label: 'LuxeStays',
      header: true,
      child: ExcludeSemantics(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.plate,
                  border: Border.all(color: colors.secondary, width: 1),
                  borderRadius: const BorderRadius.all(Radius.circular(2)),
                ),
                child: SizedBox.square(
                  dimension: 30,
                  child: Center(
                    child: Text(
                      'LS',
                      style: AppTheme.serif(
                        size: 13,
                        color: AppTheme.onPlate,
                        letterSpacing: -0.8,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'LUXESTAYS',
                style: AppTheme.serif(size: 17, letterSpacing: 4.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
