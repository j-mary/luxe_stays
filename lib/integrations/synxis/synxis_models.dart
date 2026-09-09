import '../../core/network/api_client.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/money.dart';
import '../../domain/booking.dart';
import '../../domain/rate.dart';
import '../../domain/search.dart';

/// Data-transfer objects for the SynXis contract.
///
/// These deliberately mirror the *vendor's* vocabulary (`RatePlanCode`,
/// `NightlyRates`, `ConfirmationNumber`), PascalCase and all. Domain types live
/// in `lib/domain/` and speak our vocabulary. `SynxisMappers` is the only place
/// the two meet, so a vendor rename never ripples into the UI.
///
/// Hand-written `fromJson` rather than `json_serializable` on purpose: no
/// `build_runner` step to run before the project compiles, and every field gets
/// a defensive read via [JsonRead] that names the field when a contract breaks.
class SynxisHotelDto {
  const SynxisHotelDto({
    required this.hotelId,
    required this.chainId,
    required this.name,
    required this.city,
    required this.countryCode,
    required this.starRating,
    this.address = '',
    this.latitude,
    this.longitude,
    this.currency = 'USD',
    this.brandCode,
  });

  factory SynxisHotelDto.fromJson(Map<String, Object?> json) {
    return SynxisHotelDto(
      hotelId: JsonRead.string(json, 'HotelId'),
      chainId: JsonRead.stringOrNull(json, 'ChainId') ?? '',
      name: JsonRead.string(json, 'HotelName'),
      city: JsonRead.stringOrNull(json, 'City') ?? '',
      countryCode: JsonRead.stringOrNull(json, 'CountryCode') ?? '',
      starRating: JsonRead.intOf(json, 'Rating', fallback: 5),
      address: JsonRead.stringOrNull(json, 'Address') ?? '',
      latitude: JsonRead.doubleOrNull(json, 'Latitude'),
      longitude: JsonRead.doubleOrNull(json, 'Longitude'),
      currency: JsonRead.stringOrNull(json, 'Currency') ?? 'USD',
      brandCode: JsonRead.stringOrNull(json, 'BrandCode'),
    );
  }

  final String hotelId;
  final String chainId;
  final String name;
  final String city;
  final String countryCode;
  final int starRating;
  final String address;
  final double? latitude;
  final double? longitude;
  final String currency;
  final String? brandCode;
}

class SynxisRoomTypeDto {
  const SynxisRoomTypeDto({
    required this.code,
    required this.name,
    this.description = '',
    this.maxOccupancy = 2,
    this.sizeSqm,
    this.bedding = '',
    this.mediaIds = const <String>[],
  });

  factory SynxisRoomTypeDto.fromJson(Map<String, Object?> json) {
    return SynxisRoomTypeDto(
      code: JsonRead.string(json, 'RoomTypeCode'),
      name: JsonRead.string(json, 'RoomTypeName'),
      description: JsonRead.stringOrNull(json, 'Description') ?? '',
      maxOccupancy: JsonRead.intOf(json, 'MaxOccupancy', fallback: 2),
      sizeSqm: json['SizeSqm'] == null
          ? null
          : JsonRead.intOf(json, 'SizeSqm', fallback: 0),
      bedding: JsonRead.stringOrNull(json, 'Bedding') ?? '',
      mediaIds: (json['MediaIds'] as List<Object?>? ?? const <Object?>[])
          .map((Object? e) => e.toString())
          .toList(growable: false),
    );
  }

  final String code;
  final String name;
  final String description;
  final int maxOccupancy;
  final int? sizeSqm;
  final String bedding;
  final List<String> mediaIds;

  RoomType toDomain() => RoomType(
        code: code,
        name: name,
        description: description,
        maxOccupancy: maxOccupancy,
        sizeSqm: sizeSqm,
        bedding: bedding,
        imageIds: mediaIds,
      );
}

/// A priced product for one property.
class SynxisOfferDto {
  const SynxisOfferDto({
    required this.hotelId,
    required this.roomType,
    required this.ratePlanCode,
    required this.ratePlanName,
    required this.currency,
    required this.nightlyRates,
    required this.taxesAndFeesMinor,
    required this.arrival,
    required this.departure,
    required this.adults,
    required this.childAges,
    this.quoteToken,
    this.mealPlanCode,
    this.isMemberRate = false,
    this.isRefundable = true,
    this.cancelByUtc,
    this.cancellationText = '',
    this.roomsRemaining,
    this.inclusions = const <String>[],
    this.publicTotalMinor,
  });

  factory SynxisOfferDto.fromJson(Map<String, Object?> json, String hotelId) {
    final String currency = JsonRead.stringOrNull(json, 'Currency') ?? 'USD';
    final Map<DateTime, int> nightly = <DateTime, int>{};
    for (final Map<String, Object?> night
        in JsonRead.objectList(json['NightlyRates'], 'NightlyRates')) {
      final DateTime date = JsonRead.dateOf(night, 'Date');
      nightly[date.dateOnly] =
          Money.fromApi(night['Amount'], currency).minorUnits;
    }
    return SynxisOfferDto(
      hotelId: hotelId,
      roomType: SynxisRoomTypeDto.fromJson(
        JsonRead.object(json['RoomType'], 'RoomType'),
      ),
      ratePlanCode: JsonRead.string(json, 'RatePlanCode'),
      ratePlanName: JsonRead.stringOrNull(json, 'RatePlanName') ?? '',
      currency: currency,
      nightlyRates: nightly,
      taxesAndFeesMinor:
          Money.fromApi(json['TaxesAndFees'], currency).minorUnits,
      arrival: JsonRead.dateOf(json, 'Arrival'),
      departure: JsonRead.dateOf(json, 'Departure'),
      adults: JsonRead.intOf(json, 'Adults', fallback: 2),
      childAges: (json['ChildAges'] as List<Object?>? ?? const <Object?>[])
          .map((Object? e) => int.tryParse(e.toString()) ?? 0)
          .toList(growable: false),
      quoteToken: JsonRead.stringOrNull(json, 'QuoteToken'),
      mealPlanCode: JsonRead.stringOrNull(json, 'MealPlanCode'),
      isMemberRate: JsonRead.boolOf(json, 'IsMemberRate'),
      isRefundable: JsonRead.boolOf(json, 'IsRefundable', fallback: true),
      cancelByUtc: JsonRead.dateOrNull(json, 'CancelByUtc'),
      cancellationText: JsonRead.stringOrNull(json, 'CancellationText') ?? '',
      roomsRemaining: json['RoomsRemaining'] == null
          ? null
          : JsonRead.intOf(json, 'RoomsRemaining', fallback: 0),
      inclusions: (json['Inclusions'] as List<Object?>? ?? const <Object?>[])
          .map((Object? e) => e.toString())
          .toList(growable: false),
      publicTotalMinor: json['PublicTotal'] == null
          ? null
          : Money.fromApi(json['PublicTotal'], currency).minorUnits,
    );
  }

  final String hotelId;
  final SynxisRoomTypeDto roomType;
  final String ratePlanCode;
  final String ratePlanName;
  final String currency;
  final Map<DateTime, int> nightlyRates;
  final int taxesAndFeesMinor;
  final DateTime arrival;
  final DateTime departure;
  final int adults;
  final List<int> childAges;
  final String? quoteToken;
  final String? mealPlanCode;
  final bool isMemberRate;
  final bool isRefundable;
  final DateTime? cancelByUtc;
  final String cancellationText;
  final int? roomsRemaining;
  final List<String> inclusions;
  final int? publicTotalMinor;

  /// Deterministic offer id, so the same product from two searches is the same
  /// cart line rather than a duplicate.
  String get offerId =>
      '$hotelId:${roomType.code}:$ratePlanCode:${arrival.iso8601Date}';

  RoomOffer toDomain() {
    return RoomOffer(
      offerId: offerId,
      hotelId: hotelId,
      roomType: roomType.toDomain(),
      ratePlanCode: ratePlanCode,
      ratePlanName: ratePlanName,
      stay: DateRange(arrival, departure),
      occupancy: Occupancy(adults: adults, children: childAges),
      nightlyRates: nightlyRates.map(
        (DateTime date, int minor) =>
            MapEntry<DateTime, Money>(date, Money(minor, currency)),
      ),
      taxesAndFees: Money(taxesAndFeesMinor, currency),
      cancellationPolicy: isRefundable
          ? CancellationPolicy(
              description: cancellationText.isEmpty
                  ? 'Free cancellation before the deadline shown.'
                  : cancellationText,
              freeUntil: cancelByUtc?.toLocal(),
            )
          : const CancellationPolicy.nonRefundable(),
      quotedAt: DateTime.now(),
      quoteToken: quoteToken,
      mealPlan: MealPlan.fromCode(mealPlanCode),
      isMemberRate: isMemberRate,
      isRefundable: isRefundable,
      roomsRemaining: roomsRemaining,
      inclusions: inclusions,
      strikeThroughTotal:
          publicTotalMinor == null ? null : Money(publicTotalMinor!, currency),
    );
  }
}

/// The availability response: offers grouped by property.
class SynxisAvailabilityDto {
  const SynxisAvailabilityDto({
    required this.offersByHotelId,
    this.warnings = const <String>[],
  });

  factory SynxisAvailabilityDto.fromJson(Map<String, Object?> json) {
    final Map<String, List<SynxisOfferDto>> grouped =
        <String, List<SynxisOfferDto>>{};
    for (final Map<String, Object?> entry in JsonRead.objectList(
        json['HotelAvailability'], 'HotelAvailability')) {
      final String hotelId = JsonRead.string(entry, 'HotelId');
      grouped[hotelId] = JsonRead.objectList(entry['Offers'], 'Offers')
          .map((Map<String, Object?> o) => SynxisOfferDto.fromJson(o, hotelId))
          .toList(growable: false);
    }
    return SynxisAvailabilityDto(
      offersByHotelId: grouped,
      warnings: (json['Warnings'] as List<Object?>? ?? const <Object?>[])
          .map((Object? e) => e.toString())
          .toList(growable: false),
    );
  }

  final Map<String, List<SynxisOfferDto>> offersByHotelId;

  /// SynXis returns soft warnings (e.g. "restricted rate hidden") alongside a
  /// 200. Surfacing them in logs has saved many "why is this rate missing"
  /// investigations.
  final List<String> warnings;
}

/// Reservation creation payload.
class SynxisReservationRequest {
  const SynxisReservationRequest({
    required this.hotelId,
    required this.offer,
    required this.guest,
    required this.paymentIntentId,
    this.membershipNumber,
    this.pointsRedeemed = 0,
    this.voucherCode,
    this.sourceOfBusiness = 'MOBILE_APP',
  });

  final String hotelId;
  final RoomOffer offer;
  final GuestDetails guest;

  /// The PSP intent the payment was authorised against. The CRS never sees a
  /// card - it stores the token/authorisation reference.
  final String paymentIntentId;
  final String? membershipNumber;
  final int pointsRedeemed;
  final String? voucherCode;
  final String sourceOfBusiness;

  Map<String, Object?> toJson({required String chainId}) {
    return <String, Object?>{
      'ChainId': chainId,
      'HotelId': hotelId,
      'SourceOfBusiness': sourceOfBusiness,
      'Stay': <String, Object?>{
        'Arrival': offer.stay.checkIn.iso8601Date,
        'Departure': offer.stay.checkOut.iso8601Date,
      },
      'RoomStay': <String, Object?>{
        'RoomTypeCode': offer.roomType.code,
        'RatePlanCode': offer.ratePlanCode,
        'QuoteToken': offer.quoteToken,
        'Adults': offer.occupancy.adults,
        'ChildAges': offer.occupancy.children,
        'ExpectedTotal': offer.total.asDouble,
        'Currency': offer.total.currency,
      },
      'Guest': <String, Object?>{
        'FirstName': guest.firstName,
        'LastName': guest.lastName,
        'Email': guest.email,
        'Phone': guest.phone,
        'CountryCode': guest.countryCode,
        if (guest.arrivalTime != null) 'ArrivalTime': guest.arrivalTime,
        if (guest.specialRequests.isNotEmpty)
          'SpecialRequests': guest.specialRequests,
      },
      'Payment': <String, Object?>{
        'IntentId': paymentIntentId,
        'Type': 'TOKENIZED',
      },
      'Loyalty': <String, Object?>{
        if (membershipNumber != null) 'MembershipNumber': membershipNumber,
        if (pointsRedeemed > 0) 'PointsRedeemed': pointsRedeemed,
        if (voucherCode != null) 'VoucherCode': voucherCode,
      },
    };
  }
}

class SynxisReservationDto {
  const SynxisReservationDto({
    required this.confirmationNumber,
    required this.hotelId,
    required this.hotelName,
    required this.status,
    required this.totalMinor,
    required this.currency,
    required this.createdAt,
    this.crsReservationId,
    this.itineraryUrl,
    this.paymentLast4,
  });

  factory SynxisReservationDto.fromJson(Map<String, Object?> json) {
    final String currency = JsonRead.stringOrNull(json, 'Currency') ?? 'USD';
    return SynxisReservationDto(
      confirmationNumber: JsonRead.string(json, 'ConfirmationNumber'),
      crsReservationId: JsonRead.stringOrNull(json, 'CrsReservationId'),
      hotelId: JsonRead.string(json, 'HotelId'),
      hotelName: JsonRead.stringOrNull(json, 'HotelName') ?? '',
      status: JsonRead.stringOrNull(json, 'Status') ?? 'Confirmed',
      totalMinor: Money.fromApi(json['Total'], currency).minorUnits,
      currency: currency,
      createdAt:
          JsonRead.dateOrNull(json, 'CreatedUtc') ?? DateTime.now().toUtc(),
      itineraryUrl: JsonRead.stringOrNull(json, 'ItineraryUrl'),
      paymentLast4: JsonRead.stringOrNull(json, 'PaymentLast4'),
    );
  }

  final String confirmationNumber;
  final String? crsReservationId;
  final String hotelId;
  final String hotelName;
  final String status;
  final int totalMinor;
  final String currency;
  final DateTime createdAt;
  final String? itineraryUrl;
  final String? paymentLast4;

  ReservationStatus get domainStatus => switch (status.toLowerCase()) {
        'cancelled' || 'canceled' => ReservationStatus.cancelled,
        'pending' => ReservationStatus.pending,
        'modified' => ReservationStatus.modified,
        'noshow' || 'no_show' => ReservationStatus.noShow,
        _ => ReservationStatus.confirmed,
      };
}
