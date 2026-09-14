import '../core/utils/money.dart';
import 'loyalty.dart';
import 'rate.dart';

/// A line in the shopping cart: one room, one stay, one guest party.
///
/// A luxury OTA cart is not an e-commerce cart. Each line holds inventory at a
/// *different* property, in a *different* currency potentially, with its own
/// cancellation deadline - so the cart must be able to fail partially and
/// recover, which is why every line carries its own [status].
class CartItem {
  const CartItem({
    required this.lineId,
    required this.offer,
    required this.hotelName,
    required this.hotelCity,
    this.heroImageUrl,
    this.specialRequests = '',
    this.status = CartLineStatus.ready,
    this.repriceMessage,
  });

  final String lineId;
  final RoomOffer offer;
  final String hotelName;
  final String hotelCity;
  final String? heroImageUrl;
  final String specialRequests;
  final CartLineStatus status;

  /// Populated when a re-quote moved the price; the UI shows it inline rather
  /// than silently charging a different amount.
  final String? repriceMessage;

  Money get total => offer.total;

  CartItem copyWith({
    RoomOffer? offer,
    String? specialRequests,
    CartLineStatus? status,
    String? repriceMessage,
    bool clearRepriceMessage = false,
  }) {
    return CartItem(
      lineId: lineId,
      offer: offer ?? this.offer,
      hotelName: hotelName,
      hotelCity: hotelCity,
      heroImageUrl: heroImageUrl,
      specialRequests: specialRequests ?? this.specialRequests,
      status: status ?? this.status,
      repriceMessage: clearRepriceMessage
          ? null
          : (repriceMessage ?? this.repriceMessage),
    );
  }
}

enum CartLineStatus {
  ready,
  repricing,
  priceChanged,
  soldOut,
  booked,
  failed;

  bool get blocksCheckout =>
      this == CartLineStatus.soldOut ||
      this == CartLineStatus.priceChanged ||
      this == CartLineStatus.failed;
}

/// The cart, plus the loyalty adjustments applied to it.
class Cart {
  const Cart({
    required this.id,
    this.items = const <CartItem>[],
    this.appliedVoucher,
    this.pointsToRedeem = 0,
    this.revision = 0,
    this.currency = 'USD',
  });

  final String id;
  final List<CartItem> items;

  /// A Salesforce Loyalty voucher (e.g. "20% off a suite"), issued when the
  /// member redeemed points.
  final LoyaltyVoucher? appliedVoucher;

  /// Points the guest chose to burn on this booking. Converted to money by
  /// [LoyaltyProgramRules.pointsToMoney].
  final int pointsToRedeem;

  /// Bumped on every mutation. Feeds the idempotency key, so a retry after a
  /// timeout cannot create a second reservation for the same cart state.
  final int revision;
  final String currency;

  bool get isEmpty => items.isEmpty;
  int get lineCount => items.length;
  int get roomNights =>
      items.fold(0, (int acc, CartItem i) => acc + i.offer.stay.nights);

  Money get subtotal => items.fold(
    Money.zero(currency),
    (Money acc, CartItem item) => acc + item.total,
  );

  Money voucherDiscount(LoyaltyProgramRules rules) {
    final LoyaltyVoucher? voucher = appliedVoucher;
    if (voucher == null) {
      return Money.zero(currency);
    }
    return voucher.discountOn(subtotal);
  }

  Money pointsDiscount(LoyaltyProgramRules rules) =>
      rules.pointsToMoney(pointsToRedeem, currency);

  Money total(LoyaltyProgramRules rules) {
    final Money afterVoucher = subtotal - voucherDiscount(rules);
    final Money afterPoints = afterVoucher - pointsDiscount(rules);
    return afterPoints.isNegative ? Money.zero(currency) : afterPoints;
  }

  bool get canCheckout =>
      items.isNotEmpty && items.every((CartItem i) => !i.status.blocksCheckout);

  bool get hasStaleQuote => items.any((CartItem i) => i.offer.isQuoteStale);

  Cart copyWith({
    List<CartItem>? items,
    LoyaltyVoucher? appliedVoucher,
    bool clearVoucher = false,
    int? pointsToRedeem,
    int? revision,
  }) {
    return Cart(
      id: id,
      items: items ?? this.items,
      appliedVoucher: clearVoucher
          ? null
          : (appliedVoucher ?? this.appliedVoucher),
      pointsToRedeem: pointsToRedeem ?? this.pointsToRedeem,
      revision: revision ?? this.revision,
      currency: currency,
    );
  }
}
