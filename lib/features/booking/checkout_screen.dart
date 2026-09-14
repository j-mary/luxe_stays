import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../domain/booking.dart';
import '../../domain/cart.dart';
import '../../webview/payment_webview_screen.dart';
import '../cart/cart_controller.dart';
import 'checkout_controller.dart';

/// Guest details, then the hand-off to the payment WebView.
///
/// The screen is thin on purpose. It collects a valid [GuestDetails], asks the
/// controller to begin payment, pushes [PaymentWebViewScreen], and passes
/// whatever comes back to the controller. Every decision - re-quote, verify,
/// book, accrue - happens behind `BookingRepository`.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _requests = TextEditingController();
  bool _marketingOptIn = false;

  /// Whether the guest-details form is shown. A signed-in guest whose CRM
  /// record is complete gets a summary and an Edit affordance instead: asking
  /// someone to retype what we already know is the fastest way to lose them at
  /// the last step.
  bool _editingDetails = true;

  @override
  void initState() {
    super.initState();
    final GuestDetails guest = ref.read(checkoutProvider).guest;
    _firstName.text = guest.firstName;
    _lastName.text = guest.lastName;
    _email.text = guest.email;
    _phone.text = guest.phone;
    _editingDetails = !guest.isValid;
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _requests.dispose();
    super.dispose();
  }

  GuestDetails _collect() {
    return ref
        .read(checkoutProvider)
        .guest
        .copyWith(
          firstName: _firstName.text.trim(),
          lastName: _lastName.text.trim(),
          email: _email.text.trim(),
          phone: _phone.text.trim(),
          specialRequests: _requests.text.trim(),
          marketingOptIn: _marketingOptIn,
        );
  }

  Future<void> _pay() async {
    // When the form is collapsed its fields are not in the tree, so
    // Form.validate() would trivially pass. Check the collected value instead
    // and reveal the form if anything is actually missing.
    if (!_editingDetails) {
      if (!_collect().isValid) {
        setState(() => _editingDetails = true);
        return;
      }
    } else if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final CheckoutController controller = ref.read(checkoutProvider.notifier);
    controller.updateGuest(_collect());

    final PaymentIntent? intent = await controller.beginPayment();
    if (intent == null || !mounted) {
      return;
    }

    // The WebView is a full-screen route that returns a PaymentResult. Nothing
    // else in the app knows the payment page exists.
    final PaymentResult? result = await Navigator.of(context)
        .push<PaymentResult>(
          MaterialPageRoute<PaymentResult>(
            builder: (BuildContext context) =>
                PaymentWebViewScreen(intent: intent),
            fullscreenDialog: true,
          ),
        );

    if (!mounted) {
      return;
    }
    if (result == null) {
      // Route popped without a result - treat as an abandoned payment.
      await controller.completeWithPaymentResult(
        PaymentResult(
          intentId: intent.intentId,
          status: PaymentStatus.cancelled,
        ),
      );
      return;
    }

    await controller.completeWithPaymentResult(result);
    if (!mounted) {
      return;
    }
    final CheckoutState state = ref.read(checkoutProvider);
    if (state.step == CheckoutStep.done) {
      await Navigator.of(context).pushReplacementNamed(Routes.confirmation);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CheckoutState state = ref.watch(checkoutProvider);
    final CartTotals totals = ref.watch(cartTotalsProvider);
    final Cart cart = ref.watch(cartProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: AbsorbPointer(
        absorbing: state.isBusy,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              if (state.failure != null) ...<Widget>[
                _InlineFailure(message: state.failure!.userMessage),
                const SizedBox(height: 12),
              ],
              if (!_editingDetails)
                _GuestSummary(
                  guest: state.guest,
                  onEdit: () => setState(() => _editingDetails = true),
                )
              else ...<Widget>[
                Text(
                  'Lead guest',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextFormField(
                        controller: _firstName,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'First name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (String? value) =>
                            (value == null || value.trim().length < 2)
                            ? 'Required'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lastName,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Last name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (String? value) =>
                            (value == null || value.trim().length < 2)
                            ? 'Required'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    helperText: 'Your confirmation is sent here',
                    border: OutlineInputBorder(),
                  ),
                  validator: (String? value) {
                    final GuestDetails probe = _collect().copyWith(
                      email: value ?? '',
                    );
                    return probe.isValid || (value ?? '').contains('@')
                        ? null
                        : 'Enter a valid email';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Mobile',
                    helperText:
                        'The property may contact you about your arrival',
                    border: OutlineInputBorder(),
                  ),
                  validator: (String? value) =>
                      (value == null || value.trim().length < 6)
                      ? 'Enter a contact number'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _requests,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Special requests (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _marketingOptIn,
                  onChanged: (bool? value) =>
                      setState(() => _marketingOptIn = value ?? false),
                  title: const Text('Send me LuxeStays offers'),
                  subtitle: const Text(
                    'Opt-in only. Consent is recorded against your Salesforce '
                    'contact record.',
                  ),
                ),
              ],
              const Divider(height: 32),
              _OrderSummary(cart: cart, totals: totals),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: state.isBusy ? null : _pay,
                child: state.isBusy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Pay ${totals.total.format()}'),
              ),
              const SizedBox(height: 8),
              Text(
                'Payment is taken on the provider’s secure page. LuxeStays '
                'never sees or stores your card details.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineFailure extends StatelessWidget {
  const _InlineFailure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.error_outline_rounded,
            color: theme.colorScheme.onErrorContainer,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.cart, required this.totals});

  final Cart cart;
  final CartTotals totals;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Your booking', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ...cart.items.map(
          (CartItem item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${item.hotelName} · ${item.offer.roomType.name}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(item.total.format(), style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
        if (totals.hasDiscount) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            'Rewards applied: −'
            '${(totals.voucherDiscount + totals.pointsDiscount).format()}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ],
    );
  }
}

/// What we already know about the guest, with one way to change it.
class _GuestSummary extends StatelessWidget {
  const _GuestSummary({required this.guest, required this.onEdit});

  final GuestDetails guest;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('LEAD GUEST', style: theme.textTheme.labelSmall),
                const SizedBox(height: 7),
                Text(guest.fullName, style: theme.textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(guest.email, style: theme.textTheme.bodySmall),
                Text(guest.phone, style: theme.textTheme.bodySmall),
                if (guest.membershipNumber != null) ...<Widget>[
                  const SizedBox(height: 7),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.workspace_premium_outlined,
                        size: 13,
                        color: colors.secondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        guest.membershipNumber!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.secondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          TextButton(onPressed: onEdit, child: const Text('Edit')),
        ],
      ),
    );
  }
}
