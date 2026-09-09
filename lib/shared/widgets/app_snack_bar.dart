import 'package:flutter/material.dart';

/// Shows a transient message, replacing whatever is already on screen.
///
/// `ScaffoldMessenger` **queues**. Three taps on Add produce three snack bars
/// shown back to back, each for the default four seconds, so a message about
/// the first hotel is still up while the guest is looking at the third — which
/// reads as a message that will not go away rather than as three messages.
///
/// It also sits above the `Navigator`, so an uncleared queue follows the guest
/// onto the next route. Clearing first makes the message reflect the last
/// action taken, which is the only one the guest is still thinking about.
void showAppSnackBar(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(milliseconds: 2400),
}) {
  final bool hasAction = actionLabel != null && onAction != null;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        action: hasAction
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
      ),
    );
}
