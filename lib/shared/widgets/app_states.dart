import 'package:flutter/material.dart';

import '../../core/error/failure.dart';

/// A failure rendered the way the [Failure] taxonomy says it should be.
///
/// The type of the failure - not a string match on its message - decides
/// whether a retry button appears and what the copy says. That is the practical
/// payoff of having a typed error model.
class FailureView extends StatelessWidget {
  const FailureView({
    required this.failure,
    this.onRetry,
    this.onSupport,
    super.key,
  });

  final Failure failure;
  final VoidCallback? onRetry;
  final VoidCallback? onSupport;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(_iconFor(failure), size: 44, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              failure.userMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (failure.correlationId != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Reference ${failure.correlationId}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              children: <Widget>[
                if (failure.isRetryable && onRetry != null)
                  FilledButton(onPressed: onRetry, child: const Text('Retry')),
                if (onSupport != null)
                  OutlinedButton(
                    onPressed: onSupport,
                    child: const Text('Contact us'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(Failure failure) => switch (failure) {
        NetworkFailure() => Icons.wifi_off_rounded,
        AuthFailure() => Icons.lock_outline_rounded,
        RateLimitFailure() => Icons.hourglass_bottom_rounded,
        RateChangedFailure() => Icons.price_change_outlined,
        PaymentFailure() => Icons.credit_card_off_outlined,
        _ => Icons.error_outline_rounded,
      };
}

/// Empty state with an optional call to action.
class EmptyView extends StatelessWidget {
  const EmptyView({
    required this.title,
    this.message,
    this.icon = Icons.search_off_rounded,
    this.action,
    super.key,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 44, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            if (message != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Shimmer-free skeleton, shaped like the card it stands in for.
///
/// Two deliberate choices. It does not animate: a shimmer across twenty cards
/// is a measurable battery and jank cost on low-end devices and buys very
/// little. And it matches the real card's geometry — the same 4:3 full-bleed
/// plate, the same insets, the same closing rule — so content does not jump
/// when it arrives. A loading state that reflows on resolve reads as a glitch
/// even when nothing is wrong.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    Widget bar(double widthFactor, double height) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: widthFactor,
          child: Container(
            height: height,
            color: colors.surfaceContainerHighest,
          ),
        );

    return ColoredBox(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ColoredBox(color: colors.surfaceContainerHighest),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                bar(0.26, 9),
                const SizedBox(height: 11),
                bar(0.62, 18),
                const SizedBox(height: 13),
                bar(0.88, 11),
                const SizedBox(height: 24),
                bar(0.34, 22),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: colors.outlineVariant),
        ],
      ),
    );
  }
}
