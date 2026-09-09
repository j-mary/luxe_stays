import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/analytics/analytics.dart';
import '../../core/error/failure.dart';
import '../../core/result.dart';
import '../../core/utils/ids.dart';
import '../../core/utils/money.dart';
import '../../domain/cart.dart';
import '../../domain/hotel.dart';
import '../../domain/loyalty.dart';
import '../../domain/rate.dart';
import '../account/session_controller.dart';

/// The shopping cart.
///
/// A multi-property cart is unusual in hotel booking and is the reason several
/// decisions elsewhere look the way they do: each line holds its own quote and
/// its own cancellation policy, `revision` feeds the idempotency key, and
/// checkout must be able to succeed partially.
///
/// The cart is in-memory in this POC. Production would persist it (so it
/// survives a cold start) and mirror it to the BFF (so it follows the guest
/// from phone to web), but the *shape* would not change - which is why the
/// controller exposes only value-returning mutations.
class CartController extends Notifier<Cart> {
  @override
  Cart build() => Cart(id: 'cart_${Ids.uuidV4().substring(0, 8)}');

  bool contains(String offerId) =>
      state.items.any((CartItem item) => item.offer.offerId == offerId);

  void add({
    required Hotel hotel,
    required RoomOffer offer,
    String specialRequests = '',
  }) {
    if (contains(offer.offerId)) {
      return;
    }
    final CartItem item = CartItem(
      lineId: 'line_${Ids.uuidV4().substring(0, 8)}',
      offer: offer,
      hotelName: hotel.name,
      hotelCity: hotel.city,
      heroImageUrl: hotel.heroImage?.baseUrl,
      specialRequests: specialRequests,
    );
    state = state.copyWith(
      items: <CartItem>[...state.items, item],
      revision: state.revision + 1,
    );

    ref.read(analyticsProvider).event(
      AnalyticsEvents.addToCart,
      parameters: <String, Object?>{
        'hotel_id': hotel.id,
        'offer_id': offer.offerId,
        'value_minor': offer.total.minorUnits,
        'currency': offer.total.currency,
        'nights': offer.stay.nights,
        'member_rate': offer.isMemberRate,
      },
    );
  }

  void remove(String lineId) {
    state = state.copyWith(
      items: state.items
          .where((CartItem item) => item.lineId != lineId)
          .toList(growable: false),
      revision: state.revision + 1,
    );
    if (state.items.isEmpty) {
      clearLoyaltyAdjustments();
    }
  }

  void updateSpecialRequests(String lineId, String requests) {
    state = state.copyWith(
      items: state.items
          .map(
            (CartItem item) => item.lineId == lineId
                ? item.copyWith(specialRequests: requests)
                : item,
          )
          .toList(growable: false),
      revision: state.revision + 1,
    );
  }

  void replaceItems(List<CartItem> items) {
    state = state.copyWith(items: items, revision: state.revision + 1);
  }

  /// How many points this guest may burn on the current basket.
  int maxRedeemablePoints() {
    final LoyaltyMember? member = ref.read(sessionProvider).member;
    if (member == null) {
      return 0;
    }
    return ref.read(loyaltyRulesProvider).maxRedeemablePoints(
          balance: member.pointsBalance,
          basketTotal: state.subtotal,
        );
  }

  void setPointsToRedeem(int points) {
    final int capped = points.clamp(0, maxRedeemablePoints()).toInt();
    state = state.copyWith(
      pointsToRedeem: capped,
      revision: state.revision + 1,
    );
  }

  /// Exchanges points for a Salesforce voucher and applies it to the cart.
  ///
  /// Two-step on purpose: the voucher is a real record in Salesforce with its
  /// own lifecycle, so "points spent" and "discount applied" are separate
  /// facts. If the booking later fails, the voucher still exists and can be
  /// used again - the guest does not lose their points to our error.
  Future<Result<LoyaltyVoucher>> redeemPointsForVoucher(int points) async {
    final LoyaltyMember? member = ref.read(sessionProvider).member;
    if (member == null) {
      return const Err<LoyaltyVoucher>(
        AuthFailure(
          userMessage: 'Sign in to redeem your points.',
          developerMessage: 'redeem attempted with no member in session',
        ),
      );
    }

    final Result<LoyaltyVoucher> result =
        await ref.read(salesforceRepositoryProvider).redeemPoints(
              membershipNumber: member.membershipNumber,
              points: points,
              currency: state.currency,
              cartId: state.id,
            );

    result.fold<void>(
      (LoyaltyVoucher voucher) {
        state = state.copyWith(
          appliedVoucher: voucher,
          pointsToRedeem: 0,
          revision: state.revision + 1,
        );
        ref.read(sessionProvider.notifier).applyPointsDelta(-points);
        ref.read(analyticsProvider).event(
          AnalyticsEvents.pointsRedeemed,
          parameters: <String, Object?>{
            'points': points,
            'voucher_id': voucher.id,
          },
        );
      },
      (Failure _) {},
    );
    return result;
  }

  void applyVoucher(LoyaltyVoucher voucher) {
    state = state.copyWith(
      appliedVoucher: voucher,
      revision: state.revision + 1,
    );
  }

  void clearLoyaltyAdjustments() {
    state = state.copyWith(
      clearVoucher: true,
      pointsToRedeem: 0,
      revision: state.revision + 1,
    );
  }

  void clear() {
    state = Cart(id: 'cart_${Ids.uuidV4().substring(0, 8)}');
  }
}

final NotifierProvider<CartController, Cart> cartProvider =
    NotifierProvider<CartController, Cart>(CartController.new);

/// Derived totals, so widgets never recompute pricing inline.
final Provider<CartTotals> cartTotalsProvider = Provider<CartTotals>((Ref ref) {
  final Cart cart = ref.watch(cartProvider);
  final LoyaltyProgramRules rules = ref.watch(loyaltyRulesProvider);
  final SessionState session = ref.watch(sessionProvider);
  return CartTotals(
    subtotal: cart.subtotal,
    voucherDiscount: cart.voucherDiscount(rules),
    pointsDiscount: cart.pointsDiscount(rules),
    total: cart.total(rules),
    estimatedPointsEarned: rules.estimateAccrual(
      eligibleSpend: cart.subtotal,
      tier: session.tier,
    ),
  );
});

class CartTotals {
  const CartTotals({
    required this.subtotal,
    required this.voucherDiscount,
    required this.pointsDiscount,
    required this.total,
    required this.estimatedPointsEarned,
  });

  final Money subtotal;
  final Money voucherDiscount;
  final Money pointsDiscount;
  final Money total;
  final int estimatedPointsEarned;

  bool get hasDiscount => !voucherDiscount.isZero || !pointsDiscount.isZero;
}
