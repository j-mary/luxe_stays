import '../core/utils/date_x.dart';
import '../core/utils/money.dart';
import 'search.dart';

/// A room type as configured in the CRS.
class RoomType {
  const RoomType({
    required this.code,
    required this.name,
    this.description = '',
    this.maxOccupancy = 2,
    this.sizeSqm,
    this.bedding = '',
    this.imageIds = const <String>[],
  });

  /// SynXis room-type code, e.g. `DLXK`. Stable per property.
  final String code;
  final String name;
  final String description;
  final int maxOccupancy;
  final int? sizeSqm;
  final String bedding;

  /// Leonardo media ids for this room type - the CRS knows the code, Leonardo
  /// knows the pictures, and this is the join.
  final List<String> imageIds;
}

/// A commercial product: room type + rate plan + a price for a specific stay.
///
/// This is what the guest actually adds to the cart. It is *quote-shaped*: it
/// carries [quotedAt] and [quoteToken] because hotel pricing is perishable, and
/// re-pricing at booking time is mandatory (see `docs/07-BOOKING-PAYMENT-FLOW.md`).
class RoomOffer {
  const RoomOffer({
    required this.offerId,
    required this.hotelId,
    required this.roomType,
    required this.ratePlanCode,
    required this.ratePlanName,
    required this.stay,
    required this.occupancy,
    required this.nightlyRates,
    required this.taxesAndFees,
    required this.cancellationPolicy,
    required this.quotedAt,
    this.quoteToken,
    this.mealPlan = MealPlan.roomOnly,
    this.isMemberRate = false,
    this.isRefundable = true,
    this.roomsRemaining,
    this.inclusions = const <String>[],
    this.strikeThroughTotal,
  });

  /// Our own opaque id: `hotelId:roomCode:ratePlan:checkIn`. Deterministic, so
  /// the same offer from two searches de-duplicates in the cart.
  final String offerId;
  final String hotelId;
  final RoomType roomType;
  final String ratePlanCode;
  final String ratePlanName;
  final DateRange stay;
  final Occupancy occupancy;

  /// One entry per in-house night, keyed by date. Hotels price per night, and
  /// showing an average as if it were nightly is how you get chargebacks.
  final Map<DateTime, Money> nightlyRates;
  final Money taxesAndFees;
  final CancellationPolicy cancellationPolicy;
  final DateTime quotedAt;

  /// SynXis returns a token that pins this price for a short window. It is
  /// replayed on reservation creation; if it has expired the CRS re-prices and
  /// we surface a `RateChangedFailure`.
  final String? quoteToken;
  final MealPlan mealPlan;
  final bool isMemberRate;
  final bool isRefundable;
  final int? roomsRemaining;
  final List<String> inclusions;

  /// Public rate, when a member rate beats it - used for the "you save" badge.
  final Money? strikeThroughTotal;

  String get currency => taxesAndFees.currency;

  Money get roomSubtotal => nightlyRates.values.fold(
        Money.zero(currency),
        (Money acc, Money night) => acc + night,
      );

  Money get total => roomSubtotal + taxesAndFees;

  Money get averageNightly => stay.nights == 0
      ? Money.zero(currency)
      : Money(roomSubtotal.minorUnits ~/ stay.nights, currency);

  Money? get savings {
    final Money? previous = strikeThroughTotal;
    if (previous == null || previous.minorUnits <= total.minorUnits) {
      return null;
    }
    return previous - total;
  }

  /// Quotes older than this must be re-priced before payment is taken.
  static const Duration quoteFreshness = Duration(minutes: 15);

  bool get isQuoteStale => DateTime.now().difference(quotedAt) > quoteFreshness;

  bool get isLastRooms => (roomsRemaining ?? 99) <= 3;
}

/// Free-cancellation deadline plus the penalty after it.
class CancellationPolicy {
  const CancellationPolicy({
    required this.description,
    this.freeUntil,
    this.penalty,
    this.isNonRefundable = false,
  });

  const CancellationPolicy.nonRefundable()
      : description = 'Non-refundable. This rate cannot be changed or '
            'cancelled.',
        freeUntil = null,
        penalty = null,
        isNonRefundable = true;

  final String description;
  final DateTime? freeUntil;
  final Money? penalty;
  final bool isNonRefundable;

  bool get isFreeCancellation => !isNonRefundable && freeUntil != null;

  bool freeAt(DateTime now) =>
      !isNonRefundable && freeUntil != null && now.isBefore(freeUntil!);

  String get shortLabel {
    if (isNonRefundable) {
      return 'Non-refundable';
    }
    final DateTime? until = freeUntil;
    if (until == null) {
      return 'See cancellation terms';
    }
    return 'Free cancellation until ${formatShortDate(until)}';
  }
}
