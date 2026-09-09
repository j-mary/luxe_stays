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

/// Shimmer-free skeleton. Deliberately plain: a skeleton that animates on a
/// list of 20 cards is a measurable battery and jank cost on low-end devices,
/// and buys very little.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({this.height = 240, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
