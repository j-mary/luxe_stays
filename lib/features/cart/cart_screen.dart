import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/error/failure.dart';
import '../../core/result.dart';
import '../../core/utils/date_x.dart';
import '../../domain/cart.dart';
import '../../domain/loyalty.dart';
import '../../shared/widgets/app_snack_bar.dart';
import '../../shared/widgets/app_states.dart';
import '../account/session_controller.dart';
import 'cart_controller.dart';

/// The cart, plus the loyalty controls that act on it.
///
/// This screen is where the "hotel discount + internal points" combination in
/// the brief becomes concrete: the member rate is already baked into each
/// line's price by SynXis, and on top of that the guest can burn points for a
/// Salesforce-issued voucher.
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Cart cart = ref.watch(cartProvider);
    final CartTotals totals = ref.watch(cartTotalsProvider);
    final SessionState session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Your stays')),
      body: cart.isEmpty
          ? EmptyView(
              title: 'Your cart is empty',
              message: 'Rooms you select will appear here.',
              icon: Icons.shopping_bag_outlined,
              action: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Browse hotels'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: <Widget>[
                ...cart.items.map(
                  (CartItem item) => _CartLine(
                    item: item,
                    onRemove: () =>
                        ref.read(cartProvider.notifier).remove(item.lineId),
                  ),
                ),
                if (session.isSignedIn)
                  _LoyaltyPanel(session: session, cart: cart)
                else
                  const _SignInPrompt(),
                _TotalsPanel(totals: totals, cart: cart),
              ],
            ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: cart.canCheckout
                        ? () => Navigator.of(context).pushNamed(Routes.checkout)
                        : null,
                    child: Text('Checkout · ${totals.total.format()}'),
                  ),
                ),
              ),
            ),
    );
  }
}

class _CartLine extends StatelessWidget {
  const _CartLine({required this.item, required this.onRemove});

  final CartItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(item.hotelName, style: theme.textTheme.titleMedium),
                      Text(
                        item.hotelCity,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Remove',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${item.offer.roomType.name} · ${item.offer.ratePlanName}',
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              '${formatShortDate(item.offer.stay.checkIn)} – '
              '${formatShortDate(item.offer.stay.checkOut)} · '
              '${item.offer.stay.nights} night'
              '${item.offer.stay.nights == 1 ? '' : 's'}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              item.offer.cancellationPolicy.shortLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: item.offer.cancellationPolicy.isNonRefundable
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ),
            if (item.status != CartLineStatus.ready) ...<Widget>[
              const SizedBox(height: 8),
              _StatusChip(item: item),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                item.total.format(),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (String label, Color color) = switch (item.status) {
      CartLineStatus.priceChanged => (
          item.repriceMessage ?? 'Price changed',
          theme.colorScheme.error
        ),
      CartLineStatus.soldOut => (
          'No longer available',
          theme.colorScheme.error
        ),
      CartLineStatus.repricing => (
          'Checking price…',
          theme.colorScheme.outline
        ),
      CartLineStatus.booked => ('Booked', theme.colorScheme.primary),
      CartLineStatus.failed => ('Could not book', theme.colorScheme.error),
      CartLineStatus.ready => ('', theme.colorScheme.outline),
    };
    if (label.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      children: <Widget>[
        Icon(Icons.info_outline_rounded, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _SignInPrompt extends ConsumerWidget {
  const _SignInPrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: ListTile(
        leading: const Icon(Icons.workspace_premium_rounded),
        title: const Text('Sign in to use your points'),
        subtitle:
            const Text('Members earn on every stay and unlock lower rates'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).pushNamed(Routes.loyalty),
      ),
    );
  }
}

class _LoyaltyPanel extends ConsumerStatefulWidget {
  const _LoyaltyPanel({required this.session, required this.cart});

  final SessionState session;
  final Cart cart;

  @override
  ConsumerState<_LoyaltyPanel> createState() => _LoyaltyPanelState();
}

class _LoyaltyPanelState extends ConsumerState<_LoyaltyPanel> {
  bool _redeeming = false;

  Future<void> _redeem(int points) async {
    setState(() => _redeeming = true);
    final Result<LoyaltyVoucher> result =
        await ref.read(cartProvider.notifier).redeemPointsForVoucher(points);
    if (!mounted) {
      return;
    }
    setState(() => _redeeming = false);
    result.fold<void>(
      (LoyaltyVoucher voucher) =>
          showAppSnackBar(context, '${voucher.valueLabel} applied'),
      (Failure failure) => showAppSnackBar(context, failure.userMessage),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final LoyaltyProgramRules rules = ref.watch(loyaltyRulesProvider);
    final LoyaltyMember? member = widget.session.member;
    if (member == null) {
      return const SizedBox.shrink();
    }
    final int maxPoints = ref.read(cartProvider.notifier).maxRedeemablePoints();
    final int selected = widget.cart.pointsToRedeem;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.workspace_premium_rounded,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('LuxeStays Rewards', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  '${member.pointsBalance} pts',
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${member.tier.label} · earning at '
              '${member.tier.earnMultiplier}× on this booking',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 24),
            if (widget.cart.appliedVoucher != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.confirmation_number_outlined),
                title: Text(widget.cart.appliedVoucher!.name),
                subtitle: Text(widget.cart.appliedVoucher!.valueLabel),
                trailing: TextButton(
                  onPressed: () =>
                      ref.read(cartProvider.notifier).clearLoyaltyAdjustments(),
                  child: const Text('Remove'),
                ),
              )
            else if (maxPoints == 0)
              Text(
                'You need at least ${rules.minimumRedemption} points to '
                'redeem on this booking.',
                style: theme.textTheme.bodySmall,
              )
            else ...<Widget>[
              Text(
                'Redeem up to $maxPoints points '
                '(${rules.pointsToMoney(maxPoints, widget.cart.currency).format()})',
                style: theme.textTheme.bodySmall,
              ),
              Slider(
                value: selected.toDouble(),
                max: maxPoints.toDouble(),
                divisions: (maxPoints ~/ rules.redemptionIncrement)
                    .clamp(1, 100)
                    .toInt(),
                label: '$selected pts',
                onChanged: (double value) => ref
                    .read(cartProvider.notifier)
                    .setPointsToRedeem(value.round()),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: selected < rules.minimumRedemption || _redeeming
                      ? null
                      : () => _redeem(selected),
                  child: _redeeming
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('Redeem $selected points'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TotalsPanel extends ConsumerWidget {
  const _TotalsPanel({required this.totals, required this.cart});

  final CartTotals totals;
  final Cart cart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    Widget row(String label, String value, {bool emphasise = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: emphasise
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.bodyMedium,
              ),
            ),
            Text(
              value,
              style: emphasise
                  ? theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)
                  : theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            row('Subtotal (${cart.roomNights} room nights)',
                totals.subtotal.format()),
            if (!totals.voucherDiscount.isZero)
              row('Reward voucher', '−${totals.voucherDiscount.format()}'),
            if (!totals.pointsDiscount.isZero)
              row('Points applied', '−${totals.pointsDiscount.format()}'),
            const Divider(),
            row('Total', totals.total.format(), emphasise: true),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'You will earn about ${totals.estimatedPointsEarned} points. '
                'Final points are confirmed by Salesforce after your stay.',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
