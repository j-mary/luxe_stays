import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../core/utils/date_x.dart';
import '../../domain/booking.dart';
import '../../shared/widgets/app_panel.dart';
import '../../shared/widgets/app_states.dart';
import 'checkout_controller.dart';

/// Booking confirmation.
///
/// Shows what actually happened, including the parts that did not: a partial
/// booking lists the lines that failed, and a deferred loyalty accrual is
/// labelled as pending rather than silently shown as earned. Telling the guest
/// the truth here is cheaper than the support contact that follows a
/// confirmation screen which quietly overstated things.
class ConfirmationScreen extends ConsumerWidget {
  const ConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CheckoutState state = ref.watch(checkoutProvider);
    final BookingOutcome? outcome = state.outcome;

    if (outcome == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Booking')),
        body: EmptyView(
          title: 'Nothing to show',
          message: 'This booking is no longer in progress.',
          icon: Icons.receipt_long_outlined,
          action: FilledButton(
            onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
                Routes.search, (Route<void> r) => false),
            child: const Text('Back to search'),
          ),
        ),
      );
    }

    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(outcome.isPartial ? 'Partly confirmed' : 'Confirmed'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Icon(
            outcome.isPartial
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline_rounded,
            size: 56,
            color: outcome.isPartial
                ? theme.colorScheme.error
                : theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            outcome.isPartial
                ? 'Some of your rooms are confirmed'
                : 'You are all set',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          ...outcome.reservations.map(
            (Reservation reservation) =>
                _ReservationCard(reservation: reservation),
          ),
          if (outcome.failures.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            AppPanel(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Not booked',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...outcome.failures.values.map(
                      (String message) => Text(
                        '· $message',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _LoyaltySummary(outcome: outcome),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
              Routes.search,
              (Route<void> route) => false,
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({required this.reservation});

  final Reservation reservation;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AppPanel(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(reservation.hotelName, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${formatShortDate(reservation.offer.stay.checkIn)} – '
              '${formatShortDate(reservation.offer.stay.checkOut)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Text('Confirmation', style: theme.textTheme.labelMedium),
                const Spacer(),
                SelectableText(
                  reservation.confirmationNumber,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            Row(
              children: <Widget>[
                Text('Total', style: theme.textTheme.labelMedium),
                const Spacer(),
                Text(reservation.total.format()),
              ],
            ),
            if (reservation.paymentLast4 != null)
              Row(
                children: <Widget>[
                  Text('Paid with', style: theme.textTheme.labelMedium),
                  const Spacer(),
                  Text('•••• ${reservation.paymentLast4}'),
                ],
              ),
            if (reservation.itineraryUrl != null) ...<Widget>[
              const SizedBox(height: 8),
              // The itinerary is a CMS-rendered page: it changes with the
              // brand's content, not with the app release.
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pushNamed(
                  Routes.cmsPage,
                  arguments: CmsPageArgs(
                    slug: 'itinerary',
                    title: 'Your itinerary',
                    fallbackUrl: reservation.itineraryUrl,
                  ),
                ),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('View itinerary'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LoyaltySummary extends StatelessWidget {
  const _LoyaltySummary({required this.outcome});

  final BookingOutcome outcome;

  @override
  Widget build(BuildContext context) {
    if (outcome.pointsEarned == 0 && outcome.pointsRedeemed == 0) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    return AppPanel(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.workspace_premium_rounded,
                    color: theme.colorScheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Text(
                  'LuxeStays Rewards',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (outcome.pointsRedeemed > 0)
              Text(
                '${outcome.pointsRedeemed} points redeemed',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            Text(
              outcome.loyaltyPostingDeferred
                  ? 'About ${outcome.pointsEarned} points are on their way - '
                      'we are still confirming them with our rewards system.'
                  : '${outcome.pointsEarned} points added to your balance.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
