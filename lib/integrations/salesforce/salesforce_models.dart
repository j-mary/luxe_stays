import '../../core/network/api_client.dart';
import '../../domain/loyalty.dart';

/// DTOs for the Salesforce Loyalty Management + Service Cloud objects we touch.
///
/// Salesforce field names are PascalCase with a `__c` suffix for custom fields.
/// Rather than sprinkle `LoyaltyProgramMember__c` through the app, everything
/// is normalised here into `lib/domain/loyalty.dart` types.
class SalesforceMemberDto {
  const SalesforceMemberDto({
    required this.memberId,
    required this.membershipNumber,
    required this.firstName,
    required this.lastName,
    required this.tierName,
    required this.pointsBalance,
    this.pendingPoints = 0,
    this.lifetimePoints = 0,
    this.qualifyingNights = 0,
    this.contactId,
    this.enrollmentDate,
    this.benefits = const <String>[],
  });

  /// Reads the shape returned by
  /// `GET /connect/loyalty/programs/{program}/members/{id}`.
  factory SalesforceMemberDto.fromJson(Map<String, Object?> json) {
    // The Connect API nests the currency balances; the "points" currency is
    // the one whose name matches the programme's configured point currency.
    final List<Map<String, Object?>> balances = json['memberCurrencies'] == null
        ? const <Map<String, Object?>>[]
        : JsonRead.objectList(json['memberCurrencies'], 'memberCurrencies');

    int points = JsonRead.intOf(json, 'pointsBalance', fallback: 0);
    int pending = 0;
    for (final Map<String, Object?> currency in balances) {
      final String name =
          (JsonRead.stringOrNull(currency, 'loyaltyMemberCurrencyName') ?? '')
              .toLowerCase();
      if (name.contains('point')) {
        points = JsonRead.intOf(currency, 'pointsBalance', fallback: points);
        pending = JsonRead.intOf(currency, 'escrowPointsBalance', fallback: 0);
      }
    }

    final List<Map<String, Object?>> tiers = json['memberTiers'] == null
        ? const <Map<String, Object?>>[]
        : JsonRead.objectList(json['memberTiers'], 'memberTiers');
    final String tierName = tiers.isNotEmpty
        ? (JsonRead.stringOrNull(tiers.first, 'loyaltyMemberTierName') ?? '')
        : (JsonRead.stringOrNull(json, 'tierName') ?? '');

    return SalesforceMemberDto(
      memberId: JsonRead.string(json, 'loyaltyProgramMemberId'),
      membershipNumber: JsonRead.string(json, 'membershipNumber'),
      firstName: JsonRead.stringOrNull(json, 'firstName') ?? '',
      lastName: JsonRead.stringOrNull(json, 'lastName') ?? '',
      tierName: tierName,
      pointsBalance: points,
      pendingPoints: pending,
      lifetimePoints: JsonRead.intOf(json, 'lifetimePoints', fallback: 0),
      qualifyingNights: JsonRead.intOf(json, 'qualifyingNights', fallback: 0),
      contactId: JsonRead.stringOrNull(json, 'contactId'),
      enrollmentDate: JsonRead.dateOrNull(json, 'enrollmentDate'),
      benefits: (json['memberBenefits'] as List<Object?>? ?? const <Object?>[])
          .map((Object? e) {
            if (e is Map) {
              return (e['benefitName'] ?? e['name'] ?? '').toString();
            }
            return e.toString();
          })
          .where((String s) => s.isNotEmpty)
          .toList(growable: false),
    );
  }

  final String memberId;
  final String membershipNumber;
  final String firstName;
  final String lastName;
  final String tierName;
  final int pointsBalance;
  final int pendingPoints;
  final int lifetimePoints;
  final int qualifyingNights;
  final String? contactId;
  final DateTime? enrollmentDate;
  final List<String> benefits;

  LoyaltyMember toDomain(
      {List<LoyaltyVoucher> vouchers = const <LoyaltyVoucher>[]}) {
    return LoyaltyMember(
      memberId: memberId,
      membershipNumber: membershipNumber,
      firstName: firstName,
      lastName: lastName,
      tier: LoyaltyTier.fromSalesforce(tierName),
      pointsBalance: pointsBalance,
      pendingPoints: pendingPoints,
      lifetimePoints: lifetimePoints,
      qualifyingNightsThisYear: qualifyingNights,
      memberSince: enrollmentDate,
      vouchers: vouchers,
      benefits: benefits,
      contactId: contactId,
    );
  }
}

class SalesforceVoucherDto {
  const SalesforceVoucherDto({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.expirationDate,
    required this.status,
    this.discountPercent,
    this.faceValue,
    this.currency = 'USD',
    this.minimumSpend,
  });

  factory SalesforceVoucherDto.fromJson(Map<String, Object?> json) {
    return SalesforceVoucherDto(
      id: JsonRead.string(json, 'voucherId'),
      code: JsonRead.stringOrNull(json, 'voucherCode') ?? '',
      name: JsonRead.stringOrNull(json, 'voucherDefinitionName') ??
          JsonRead.stringOrNull(json, 'name') ??
          'Reward',
      type: JsonRead.stringOrNull(json, 'type') ?? 'Discount',
      expirationDate: JsonRead.dateOrNull(json, 'expirationDate') ??
          DateTime.now().add(const Duration(days: 365)),
      status: JsonRead.stringOrNull(json, 'status') ?? 'Issued',
      discountPercent: JsonRead.doubleOrNull(json, 'discountPercent'),
      faceValue: JsonRead.doubleOrNull(json, 'faceValue'),
      currency: JsonRead.stringOrNull(json, 'currencyIsoCode') ?? 'USD',
      minimumSpend: JsonRead.doubleOrNull(json, 'minimumSpend'),
    );
  }

  final String id;
  final String code;
  final String name;

  /// Salesforce voucher type: `Discount` (percentage) or `Value` (fixed).
  final String type;
  final DateTime expirationDate;
  final String status;
  final double? discountPercent;
  final double? faceValue;
  final String currency;
  final double? minimumSpend;

  LoyaltyVoucher toDomain() {
    final bool isPercent = type.toLowerCase() == 'discount';
    return LoyaltyVoucher(
      id: id,
      code: code,
      name: name,
      type: isPercent ? VoucherType.percentOff : VoucherType.fixedAmount,
      expiresAt: expirationDate,
      percentOff: discountPercent,
      valueMinor: faceValue == null ? null : (faceValue! * 100).round(),
      currency: currency,
      status: switch (status.toLowerCase()) {
        'redeemed' => VoucherStatus.redeemed,
        'reserved' => VoucherStatus.reserved,
        'expired' => VoucherStatus.expired,
        'cancelled' || 'canceled' => VoucherStatus.cancelled,
        _ => VoucherStatus.issued,
      },
      minimumSpendMinor:
          minimumSpend == null ? null : (minimumSpend! * 100).round(),
    );
  }
}

class SalesforceLedgerEntryDto {
  const SalesforceLedgerEntryDto({
    required this.id,
    required this.eventDate,
    required this.points,
    required this.description,
    required this.eventType,
    this.journalReference,
    this.hotelName,
  });

  factory SalesforceLedgerEntryDto.fromJson(Map<String, Object?> json) {
    final double credit = JsonRead.doubleOrNull(json, 'Points') ?? 0;
    return SalesforceLedgerEntryDto(
      id: JsonRead.string(json, 'Id'),
      eventDate: JsonRead.dateOrNull(json, 'EventDate') ?? DateTime.now(),
      points: credit.round(),
      description: JsonRead.stringOrNull(json, 'Description') ?? '',
      eventType: JsonRead.stringOrNull(json, 'EventType') ?? 'Accrual',
      journalReference: JsonRead.stringOrNull(json, 'JournalReference'),
      hotelName: JsonRead.stringOrNull(json, 'HotelName'),
    );
  }

  final String id;
  final DateTime eventDate;
  final int points;
  final String description;
  final String eventType;
  final String? journalReference;
  final String? hotelName;

  PointsLedgerEntry toDomain() => PointsLedgerEntry(
        id: id,
        occurredAt: eventDate,
        points: points,
        description: description,
        type: switch (eventType.toLowerCase()) {
          'redemption' => LedgerEntryType.redemption,
          'expiration' || 'expiry' => LedgerEntryType.expiry,
          'adjustment' => LedgerEntryType.adjustment,
          'tierbonus' || 'tier_bonus' => LedgerEntryType.tierBonus,
          _ => LedgerEntryType.accrual,
        },
        bookingReference: journalReference,
        hotelName: hotelName,
      );
}

/// Result of running a loyalty program process (accrual or redemption).
class SalesforceProcessResult {
  const SalesforceProcessResult({
    required this.status,
    required this.transactionJournalId,
    this.pointsChange = 0,
    this.newBalance,
    this.voucher,
    this.message,
  });

  factory SalesforceProcessResult.fromJson(Map<String, Object?> json) {
    final Object outputs = json['outputParameters'] ?? json;
    final Map<String, Object?> out =
        JsonRead.object(outputs, 'outputParameters');
    return SalesforceProcessResult(
      status: JsonRead.stringOrNull(json, 'status') ??
          JsonRead.stringOrNull(out, 'status') ??
          'Success',
      transactionJournalId:
          JsonRead.stringOrNull(out, 'transactionJournalId') ?? '',
      pointsChange: JsonRead.intOf(out, 'points', fallback: 0),
      newBalance: out['newBalance'] == null
          ? null
          : JsonRead.intOf(out, 'newBalance', fallback: 0),
      voucher: out['voucher'] == null
          ? null
          : SalesforceVoucherDto.fromJson(
              JsonRead.object(out['voucher'], 'voucher'),
            ),
      message: JsonRead.stringOrNull(out, 'message'),
    );
  }

  final String status;

  /// The `TransactionJournal` record id. This is the audit trail: every point
  /// movement in Salesforce hangs off one, and it is what finance reconciles
  /// against a booking.
  final String transactionJournalId;
  final int pointsChange;
  final int? newBalance;
  final SalesforceVoucherDto? voucher;
  final String? message;

  bool get isSuccess => status.toLowerCase() == 'success';
}
