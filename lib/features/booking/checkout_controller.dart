import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/error/failure.dart';
import '../../core/result.dart';
import '../../data/booking_repository.dart';
import '../../domain/booking.dart';
import '../../domain/cart.dart';
import '../../domain/loyalty.dart';
import '../account/session_controller.dart';
import '../cart/cart_controller.dart';

enum CheckoutStep {
  details,
  revalidating,
  awaitingPayment,
  confirming,
  done,
  failed,
}

class CheckoutState {
  const CheckoutState({
    required this.guest,
    this.step = CheckoutStep.details,
    this.intent,
    this.outcome,
    this.failure,
    this.lineProblems = const <String, String>{},
  });

  final GuestDetails guest;
  final CheckoutStep step;
  final PaymentIntent? intent;
  final BookingOutcome? outcome;
  final Failure? failure;
  final Map<String, String> lineProblems;

  bool get isBusy =>
      step == CheckoutStep.revalidating || step == CheckoutStep.confirming;

  CheckoutState copyWith({
    GuestDetails? guest,
    CheckoutStep? step,
    PaymentIntent? intent,
    BookingOutcome? outcome,
    Failure? failure,
    Map<String, String>? lineProblems,
    bool clearFailure = false,
  }) {
    return CheckoutState(
      guest: guest ?? this.guest,
      step: step ?? this.step,
      intent: intent ?? this.intent,
      outcome: outcome ?? this.outcome,
      failure: clearFailure ? null : (failure ?? this.failure),
      lineProblems: lineProblems ?? this.lineProblems,
    );
  }
}

/// Drives the three-phase checkout described in `BookingRepository`.
///
/// The controller owns the *sequence*; the screen owns the WebView. Splitting
/// it that way is what makes the flow testable: every step here can be driven
/// from a unit test with a fake repository, and the only thing that needs a
/// widget test is the WebView hand-off itself.
class CheckoutController extends Notifier<CheckoutState> {
  @override
  CheckoutState build() {
    // `read`, not `watch`: a loyalty refresh landing mid-checkout must not
    // rebuild this notifier and discard the guest's typed details - or, worse,
    // the booking outcome the confirmation screen is showing.
    final SessionState session = ref.read(sessionProvider);
    final LoyaltyMember? member = session.member;
    return CheckoutState(
      guest: GuestDetails(
        firstName: member?.firstName ?? '',
        lastName: member?.lastName ?? '',
        email: '',
        phone: '',
        membershipNumber: member?.membershipNumber,
      ),
    );
  }

  void updateGuest(GuestDetails guest) {
    state = state.copyWith(guest: guest, clearFailure: true);
  }

  /// Phase 1 + 2: re-quote, then create the payment intent.
  ///
  /// Returns the intent when the screen should open the payment WebView, or
  /// null when something needs the guest's attention first.
  Future<PaymentIntent?> beginPayment() async {
    if (!state.guest.isValid) {
      state = state.copyWith(
        failure: const ClientFailure(
          userMessage: 'Please complete the guest details.',
          developerMessage: 'guest details invalid',
          statusCode: 422,
        ),
      );
      return null;
    }

    state = state.copyWith(
      step: CheckoutStep.revalidating,
      clearFailure: true,
      lineProblems: const <String, String>{},
    );

    final BookingRepository repository = ref.read(bookingRepositoryProvider);
    final Cart cart = ref.read(cartProvider);

    // Phase 1 - re-quote every line against SynXis.
    final CheckoutPreparation preparation = await repository.prepare(cart);
    ref.read(cartProvider.notifier).replaceItems(preparation.cart.items);

    if (!preparation.canProceed) {
      state = state.copyWith(
        step: CheckoutStep.details,
        lineProblems: preparation.problems,
        failure: RateChangedFailure(
          userMessage: 'Some prices changed while you were booking. '
              'Please review your cart.',
          developerMessage: 'preparation blocked: ${preparation.problems}',
          previousTotalMinor: cart.subtotal.minorUnits,
          currentTotalMinor: preparation.cart.subtotal.minorUnits,
          currency: cart.currency,
        ),
      );
      return null;
    }

    // Phase 2 - create the payment intent for the (possibly updated) total.
    final Result<PaymentIntent> intentResult =
        await repository.createPaymentIntent(
      cart: ref.read(cartProvider),
      rules: ref.read(loyaltyRulesProvider),
      returnUrl: 'luxestays://payment-success',
      membershipNumber: ref.read(sessionProvider).membershipNumber,
    );

    return intentResult.fold<PaymentIntent?>(
      (PaymentIntent intent) {
        state = state.copyWith(
          step: CheckoutStep.awaitingPayment,
          intent: intent,
        );
        return intent;
      },
      (Failure failure) {
        state = state.copyWith(step: CheckoutStep.failed, failure: failure);
        return null;
      },
    );
  }

  /// Phase 3: the WebView returned. Verify, book, accrue.
  Future<void> completeWithPaymentResult(PaymentResult result) async {
    if (result.status == PaymentStatus.cancelled) {
      state = state.copyWith(step: CheckoutStep.details);
      return;
    }

    state = state.copyWith(step: CheckoutStep.confirming, clearFailure: true);

    final Result<BookingOutcome> outcome =
        await ref.read(bookingRepositoryProvider).complete(
              cart: ref.read(cartProvider),
              guest: state.guest,
              bridgeResult: result,
              rules: ref.read(loyaltyRulesProvider),
              member: ref.read(sessionProvider).member,
            );

    state = outcome.fold<CheckoutState>(
      (BookingOutcome booking) {
        // The cart has served its purpose; clearing it here (not in the UI)
        // guarantees a back-navigation cannot re-submit it.
        ref.read(cartProvider.notifier).clear();
        // Balance and tier will have moved; refresh from Salesforce.
        unawaited(ref.read(sessionProvider.notifier).refresh());
        return state.copyWith(step: CheckoutStep.done, outcome: booking);
      },
      (Failure failure) =>
          state.copyWith(step: CheckoutStep.failed, failure: failure),
    );
  }

  void reset() {
    state = build();
  }
}

final NotifierProvider<CheckoutController, CheckoutState> checkoutProvider =
    NotifierProvider<CheckoutController, CheckoutState>(
  CheckoutController.new,
);
