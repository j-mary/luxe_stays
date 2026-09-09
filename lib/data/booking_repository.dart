import '../core/analytics/analytics.dart';
import '../core/error/failure.dart';
import '../core/logging/app_logger.dart';
import '../core/result.dart';
import '../core/utils/ids.dart';
import '../core/utils/money.dart';
import '../domain/booking.dart';
import '../domain/cart.dart';
import '../domain/loyalty.dart';
import '../domain/rate.dart';
import '../integrations/payments/payment_api.dart';
import '../integrations/salesforce/salesforce_repository.dart';
import '../integrations/synxis/synxis_repository.dart';

/// Checkout orchestration across SynXis, the PSP and Salesforce.
///
/// The flow is deliberately split into three awaited steps with the WebView in
/// between, because the middle step does not belong to us:
///
/// ```
/// 1. prepare()          re-quote every cart line against SynXis
///        ↓
/// 2. createPaymentIntent()  →  WebView hosted page  →  bridge result
///        ↓
/// 3. complete()         verify payment server-side, create reservations,
///                       then post loyalty accrual (non-blocking)
/// ```
///
/// Failure semantics, in order of how much they matter:
///  * **Money moved but no reservation** is the unacceptable outcome. Payment
///    is therefore authorised (not captured) before booking, and a booking
///    failure triggers a void/refund request rather than a silent loss.
///  * **Reservation made but loyalty not posted** is acceptable and recoverable
///    - it goes to a retry outbox.
///  * **Price changed between steps 1 and 3** stops the flow and asks the guest.
class BookingRepository {
  BookingRepository({
    required SynxisRepository synxis,
    required PaymentApi payments,
    required SalesforceRepository salesforce,
    required AnalyticsService analytics,
    required AppLogger logger,
  })  : _synxis = synxis,
        _payments = payments,
        _salesforce = salesforce,
        _analytics = analytics,
        _logger = logger;

  final SynxisRepository _synxis;
  final PaymentApi _payments;
  final SalesforceRepository _salesforce;
  final AnalyticsService _analytics;
  final AppLogger _logger;

  /// Step 1 - re-quote every line. Returns a cart whose lines carry fresh
  /// prices, or flags the ones that moved so the UI can ask the guest.
  Future<CheckoutPreparation> prepare(Cart cart) async {
    final List<CartItem> updated = <CartItem>[];
    final Map<String, String> problems = <String, String>{};

    for (final CartItem item in cart.items) {
      final Result<RoomOffer> result = await _synxis.revalidate(item.offer);
      result.fold<void>(
        (RoomOffer fresh) => updated.add(
          item.copyWith(
            offer: fresh,
            status: CartLineStatus.ready,
            clearRepriceMessage: true,
          ),
        ),
        (Failure failure) {
          if (failure is RateChangedFailure) {
            problems[item.lineId] = failure.userMessage;
            updated.add(
              item.copyWith(
                status: CartLineStatus.priceChanged,
                repriceMessage:
                    'Now ${Money(failure.currentTotalMinor, failure.currency).format()}',
              ),
            );
          } else {
            problems[item.lineId] = failure.userMessage;
            updated.add(item.copyWith(status: CartLineStatus.soldOut));
          }
        },
      );
    }

    final Cart prepared =
        cart.copyWith(items: updated, revision: cart.revision + 1);
    _logger.info(
      'checkout prepared',
      context: <String, Object?>{
        'cartId': cart.id,
        'lines': updated.length,
        'problems': problems.length,
      },
    );
    return CheckoutPreparation(cart: prepared, problems: problems);
  }

  /// Step 2 - create the intent the hosted payment page will be opened for.
  Future<Result<PaymentIntent>> createPaymentIntent({
    required Cart cart,
    required LoyaltyProgramRules rules,
    required String returnUrl,
    String? membershipNumber,
  }) async {
    final Money amount = cart.total(rules);
    _analytics.event(
      AnalyticsEvents.beginCheckout,
      parameters: <String, Object?>{
        'cart_id': cart.id,
        'value_minor': amount.minorUnits,
        'currency': amount.currency,
        'lines': cart.lineCount,
        'points_redeemed': cart.pointsToRedeem,
      },
    );
    return _payments.createIntent(
      amount: amount,
      cartId: cart.id,
      returnUrl: returnUrl,
      membershipNumber: membershipNumber,
      idempotencyKey: Ids.idempotencyKeyFor(cart.id, cart.revision),
      metadata: <String, Object?>{
        'lineCount': cart.lineCount,
        'roomNights': cart.roomNights,
      },
    );
  }

  /// Step 3 - verify the payment, book every line, then post loyalty.
  Future<Result<BookingOutcome>> complete({
    required Cart cart,
    required GuestDetails guest,
    required PaymentResult bridgeResult,
    required LoyaltyProgramRules rules,
    LoyaltyMember? member,
  }) async {
    // 3a. Never trust the WebView. Confirm with the PSP, server side.
    final Result<PaymentResult> verified =
        await _payments.verifyIntent(bridgeResult.intentId);
    final PaymentResult? payment = verified.valueOrNull;
    if (payment == null) {
      return Err<BookingOutcome>(verified.failureOrNull!);
    }
    if (!payment.isAuthorized) {
      _logger.warn(
        'payment not authorized at verification',
        context: <String, Object?>{
          'intentId': payment.intentId,
          'status': payment.status.name,
          'bridgeClaimed': bridgeResult.status.name,
        },
      );
      return Err<BookingOutcome>(
        PaymentFailure(
          userMessage: payment.declineReason ??
              'Your payment was not completed. No charge has been made.',
          developerMessage:
              'intent ${payment.intentId} status=${payment.status.name}',
          reason: switch (payment.status) {
            PaymentStatus.declined => PaymentFailureReason.declined,
            PaymentStatus.cancelled => PaymentFailureReason.cancelledByUser,
            PaymentStatus.pending => PaymentFailureReason.timeout,
            _ => PaymentFailureReason.unknown,
          },
        ),
      );
    }

    // 3b. One reservation per cart line.
    final List<Reservation> reservations = <Reservation>[];
    final Map<String, String> failures = <String, String>{};

    for (final CartItem item in cart.items) {
      final Result<Reservation> result = await _synxis.book(
        offer: item.offer,
        guest: guest,
        hotelName: item.hotelName,
        paymentIntentId: payment.intentId,
        idempotencyKey: '${Ids.idempotencyKeyFor(cart.id, cart.revision)}'
            '_${item.lineId}',
        membershipNumber: member?.membershipNumber,
        pointsRedeemed: cart.pointsToRedeem,
        voucherCode: cart.appliedVoucher?.code,
      );
      result.fold<void>(
        reservations.add,
        (Failure failure) {
          failures[item.lineId] = failure.userMessage;
          _logger.error(
            'reservation failed for line ${item.lineId}',
            correlationId: failure.correlationId,
            error: failure,
          );
        },
      );
    }

    if (reservations.isEmpty) {
      // Money was authorised but nothing was booked. The authorisation is
      // voided by the BFF on this signal; the guest is never left paying for
      // nothing.
      _logger.error(
        'all reservations failed after authorization - void required',
        context: <String, Object?>{'intentId': payment.intentId},
      );
      return Err<BookingOutcome>(
        ServerFailure(
          userMessage: 'We could not confirm your booking and your card has '
              'not been charged. Please try again.',
          developerMessage: 'no reservations created for cart ${cart.id}; '
              'void requested for intent ${payment.intentId}',
          statusCode: 502,
        ),
      );
    }

    // 3c. Loyalty. Explicitly after the point of no return, and explicitly
    // allowed to fail.
    int pointsEarned = 0;
    bool deferred = false;
    if (member != null) {
      final Money eligible = _eligibleSpend(reservations, rules);
      final AccrualOutcome outcome = await _salesforce.postAccrual(
        membershipNumber: member.membershipNumber,
        reservation: reservations.first,
        eligibleSpend: eligible,
      );
      pointsEarned = outcome.points;
      deferred = !outcome.isPosted;
    }

    for (final Reservation reservation in reservations) {
      _analytics.purchase(
        transactionId: reservation.confirmationNumber,
        valueMinor: reservation.total.minorUnits,
        currency: reservation.total.currency,
        pointsEarned: pointsEarned,
      );
    }

    return Ok<BookingOutcome>(
      BookingOutcome(
        reservations: reservations
            .map((Reservation r) => r.copyWith(pointsEarned: pointsEarned))
            .toList(growable: false),
        failures: failures,
        pointsEarned: pointsEarned,
        pointsRedeemed: cart.pointsToRedeem,
        loyaltyPostingDeferred: deferred,
      ),
    );
  }

  /// Points are earned on room revenue, not on tax and fees. Getting this
  /// wrong is the loyalty bug that generates the most support contacts.
  Money _eligibleSpend(
      List<Reservation> reservations, LoyaltyProgramRules rules) {
    final String currency = reservations.first.total.currency;
    Money eligible = Money.zero(currency);
    for (final Reservation reservation in reservations) {
      eligible = eligible +
          (rules.taxesEarnPoints
              ? reservation.offer.total
              : reservation.offer.roomSubtotal);
    }
    return eligible;
  }

  Future<Result<bool>> cancel(String confirmationNumber, String reason) =>
      _synxis.cancel(confirmationNumber, reason);
}

class CheckoutPreparation {
  const CheckoutPreparation({required this.cart, required this.problems});

  final Cart cart;

  /// Line id → guest-facing message. Empty means "go ahead".
  final Map<String, String> problems;

  bool get canProceed => problems.isEmpty && cart.canCheckout;
}
