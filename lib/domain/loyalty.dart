import '../core/utils/money.dart';

/// LuxeStays Rewards - the internal points programme, backed by Salesforce
/// Loyalty Management.
///
/// Two mechanics are combined, exactly as the brief describes:
///  1. **Hotel discounts** - a member-rate price advantage negotiated per
///     property and surfaced by SynXis as a separate rate plan.
///  2. **Points** - earned on eligible spend, burnable against a future stay.
///
/// Salesforce is the *system of record* for balances. The client never
/// computes an authoritative balance; [LoyaltyProgramRules] exists only to
/// render accurate previews ("you'll earn ~4,500 points") before the accrual
/// journal is actually posted.
enum LoyaltyTier {
  classic,
  silver,
  gold,
  platinum;

  /// Nights required in a membership year to reach the tier.
  int get qualifyingNights => switch (this) {
    LoyaltyTier.classic => 0,
    LoyaltyTier.silver => 10,
    LoyaltyTier.gold => 25,
    LoyaltyTier.platinum => 50,
  };

  /// Points per unit of eligible spend multiplier.
  double get earnMultiplier => switch (this) {
    LoyaltyTier.classic => 1.0,
    LoyaltyTier.silver => 1.25,
    LoyaltyTier.gold => 1.5,
    LoyaltyTier.platinum => 2.0,
  };

  /// The member-rate discount the tier unlocks, as a percentage.
  double get memberRateDiscountPercent => switch (this) {
    LoyaltyTier.classic => 5,
    LoyaltyTier.silver => 8,
    LoyaltyTier.gold => 12,
    LoyaltyTier.platinum => 15,
  };

  String get label => switch (this) {
    LoyaltyTier.classic => 'Classic',
    LoyaltyTier.silver => 'Silver',
    LoyaltyTier.gold => 'Gold',
    LoyaltyTier.platinum => 'Platinum',
  };

  LoyaltyTier? get next => switch (this) {
    LoyaltyTier.classic => LoyaltyTier.silver,
    LoyaltyTier.silver => LoyaltyTier.gold,
    LoyaltyTier.gold => LoyaltyTier.platinum,
    LoyaltyTier.platinum => null,
  };

  /// Salesforce stores the tier as a picklist string on `LoyaltyMemberTier`.
  static LoyaltyTier fromSalesforce(String? raw) =>
      switch (raw?.toLowerCase().trim()) {
        'platinum' => LoyaltyTier.platinum,
        'gold' => LoyaltyTier.gold,
        'silver' => LoyaltyTier.silver,
        _ => LoyaltyTier.classic,
      };
}

class LoyaltyMember {
  const LoyaltyMember({
    required this.memberId,
    required this.membershipNumber,
    required this.firstName,
    required this.lastName,
    required this.tier,
    required this.pointsBalance,
    this.pendingPoints = 0,
    this.lifetimePoints = 0,
    this.qualifyingNightsThisYear = 0,
    this.memberSince,
    this.vouchers = const <LoyaltyVoucher>[],
    this.benefits = const <String>[],
    this.contactId,
    this.email,
    this.phone,
  });

  /// Salesforce `LoyaltyProgramMember.Id`.
  final String memberId;

  /// The number the guest sees and quotes to a hotel.
  final String membershipNumber;
  final String firstName;
  final String lastName;
  final LoyaltyTier tier;

  /// Redeemable balance from the Salesforce loyalty ledger.
  final int pointsBalance;

  /// Accrued but not yet posted (typically until after check-out).
  final int pendingPoints;
  final int lifetimePoints;
  final int qualifyingNightsThisYear;
  final DateTime? memberSince;
  final List<LoyaltyVoucher> vouchers;
  final List<String> benefits;

  /// Salesforce `Contact.Id` - the CRM identity behind the membership.
  final String? contactId;

  /// Contact details from the CRM. Present so that checkout does not ask a
  /// signed-in guest to retype what Salesforce already holds.
  final String? email;
  final String? phone;

  String get displayName => '$firstName $lastName';

  List<LoyaltyVoucher> get usableVouchers =>
      vouchers.where((LoyaltyVoucher v) => v.isUsable).toList(growable: false);

  int? get nightsToNextTier {
    final LoyaltyTier? next = tier.next;
    if (next == null) {
      return null;
    }
    final int remaining = next.qualifyingNights - qualifyingNightsThisYear;
    return remaining <= 0 ? 0 : remaining;
  }

  double get progressToNextTier {
    final LoyaltyTier? next = tier.next;
    if (next == null || next.qualifyingNights == 0) {
      return 1;
    }
    return (qualifyingNightsThisYear / next.qualifyingNights)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  LoyaltyMember copyWith({
    int? pointsBalance,
    int? pendingPoints,
    List<LoyaltyVoucher>? vouchers,
    LoyaltyTier? tier,
  }) {
    return LoyaltyMember(
      memberId: memberId,
      membershipNumber: membershipNumber,
      firstName: firstName,
      lastName: lastName,
      tier: tier ?? this.tier,
      pointsBalance: pointsBalance ?? this.pointsBalance,
      pendingPoints: pendingPoints ?? this.pendingPoints,
      lifetimePoints: lifetimePoints,
      qualifyingNightsThisYear: qualifyingNightsThisYear,
      memberSince: memberSince,
      vouchers: vouchers ?? this.vouchers,
      benefits: benefits,
      contactId: contactId,
      email: email,
      phone: phone,
    );
  }
}

/// A Salesforce Loyalty voucher: a discount instrument issued to a member,
/// usually in exchange for points.
class LoyaltyVoucher {
  const LoyaltyVoucher({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.expiresAt,
    this.percentOff,
    this.valueMinor,
    this.currency = 'USD',
    this.status = VoucherStatus.issued,
    this.minimumSpendMinor,
  });

  final String id;
  final String code;
  final String name;
  final VoucherType type;
  final DateTime expiresAt;
  final double? percentOff;
  final int? valueMinor;
  final String currency;
  final VoucherStatus status;
  final int? minimumSpendMinor;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isUsable => status == VoucherStatus.issued && !isExpired;

  Money discountOn(Money subtotal) {
    if (!isUsable) {
      return Money.zero(subtotal.currency);
    }
    final int? minimum = minimumSpendMinor;
    if (minimum != null && subtotal.minorUnits < minimum) {
      return Money.zero(subtotal.currency);
    }
    return switch (type) {
      VoucherType.percentOff => subtotal.percentage(percentOff ?? 0),
      VoucherType.fixedAmount => Money(valueMinor ?? 0, subtotal.currency),
    };
  }

  String get valueLabel => switch (type) {
    VoucherType.percentOff => '${(percentOff ?? 0).toStringAsFixed(0)}% off',
    VoucherType.fixedAmount =>
      '${Money(valueMinor ?? 0, currency).format()} off',
  };
}

enum VoucherType { percentOff, fixedAmount }

enum VoucherStatus { issued, reserved, redeemed, expired, cancelled }

/// One row of the points ledger.
class PointsLedgerEntry {
  const PointsLedgerEntry({
    required this.id,
    required this.occurredAt,
    required this.points,
    required this.description,
    required this.type,
    this.bookingReference,
    this.hotelName,
  });

  final String id;
  final DateTime occurredAt;

  /// Positive for accrual, negative for redemption.
  final int points;
  final String description;
  final LedgerEntryType type;
  final String? bookingReference;
  final String? hotelName;

  bool get isAccrual => points > 0;
}

enum LedgerEntryType { accrual, redemption, expiry, adjustment, tierBonus }

/// Client-side mirror of the programme's earn/burn maths.
///
/// **This is a preview, not an authority.** Salesforce runs the real accrual
/// through its program processes; if the two disagree, Salesforce wins and the
/// UI reconciles on the next member fetch. Keeping the rules in one value
/// object makes that assumption explicit - and makes it unit-testable.
class LoyaltyProgramRules {
  const LoyaltyProgramRules({
    this.basePointsPerCurrencyUnit = 10,
    this.pointValueMinorUnits = 1,
    this.minimumRedemption = 2000,
    this.redemptionIncrement = 500,
    this.taxesEarnPoints = false,
  });

  /// Points per whole unit of eligible spend (e.g. 10 points per USD).
  final int basePointsPerCurrencyUnit;

  /// What one point is worth in minor units when redeemed (1 point = 1 cent).
  final int pointValueMinorUnits;
  final int minimumRedemption;
  final int redemptionIncrement;

  /// Most programmes exclude tax and fees from accrual. Getting this wrong is
  /// the single most common loyalty support ticket.
  final bool taxesEarnPoints;

  int estimateAccrual({
    required Money eligibleSpend,
    required LoyaltyTier tier,
  }) {
    final int wholeUnits = eligibleSpend.minorUnits ~/ 100;
    final double raw =
        wholeUnits * basePointsPerCurrencyUnit * tier.earnMultiplier;
    return raw.floor();
  }

  Money pointsToMoney(int points, String currency) =>
      Money(points * pointValueMinorUnits, currency);

  /// How many points the guest may burn on a given basket: capped by balance,
  /// by the basket value, and snapped to the redemption increment.
  int maxRedeemablePoints({required int balance, required Money basketTotal}) {
    if (balance < minimumRedemption) {
      return 0;
    }
    final int pointsForFullBasket =
        basketTotal.minorUnits ~/ pointValueMinorUnits;
    final int capped = balance < pointsForFullBasket
        ? balance
        : pointsForFullBasket;
    final int snapped = (capped ~/ redemptionIncrement) * redemptionIncrement;
    return snapped < minimumRedemption ? 0 : snapped;
  }
}
