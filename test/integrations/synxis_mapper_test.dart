import 'package:flutter_test/flutter_test.dart';
import 'package:luxe_stays/core/error/failure.dart';
import 'package:luxe_stays/domain/booking.dart';
import 'package:luxe_stays/domain/rate.dart';
import 'package:luxe_stays/domain/search.dart';
import 'package:luxe_stays/integrations/synxis/synxis_models.dart';

Map<String, Object?> _offerJson({
  bool refundable = true,
  bool memberRate = false,
  Object? taxes = 84.0,
}) {
  return <String, Object?>{
    'RoomType': <String, Object?>{
      'RoomTypeCode': 'DLX',
      'RoomTypeName': 'Deluxe room',
      'Description': 'Courtyard view',
      'MaxOccupancy': 2,
      'SizeSqm': 32,
      'Bedding': 'King',
    },
    'RatePlanCode': 'BARBB',
    'RatePlanName': 'Bed & breakfast',
    'Currency': 'EUR',
    'NightlyRates': <Object?>[
      <String, Object?>{'Date': '2026-11-12', 'Amount': 300.0},
      <String, Object?>{'Date': '2026-11-13', 'Amount': 300.0},
    ],
    'TaxesAndFees': taxes,
    'Arrival': '2026-11-12',
    'Departure': '2026-11-14',
    'Adults': 2,
    'ChildAges': <Object?>[6],
    'QuoteToken': 'qt_abc',
    'MealPlanCode': 'BB',
    'IsMemberRate': memberRate,
    'IsRefundable': refundable,
    'CancelByUtc': '2026-11-10T12:00:00Z',
    'CancellationText': 'Free until 48h before arrival.',
    'RoomsRemaining': 2,
    'Inclusions': <Object?>['Breakfast for two'],
    if (memberRate) 'PublicTotal': 780.0,
  };
}

void main() {
  group('SynxisOfferDto → RoomOffer', () {
    test('maps nightly rates, taxes and totals in minor units', () {
      final RoomOffer offer =
          SynxisOfferDto.fromJson(_offerJson(), 'H-PAR-001').toDomain();

      expect(offer.hotelId, 'H-PAR-001');
      expect(offer.stay.nights, 2);
      expect(offer.nightlyRates.length, 2);
      expect(offer.roomSubtotal.minorUnits, 60000);
      expect(offer.taxesAndFees.minorUnits, 8400);
      expect(offer.total.minorUnits, 68400);
      expect(offer.averageNightly.minorUnits, 30000);
      expect(offer.mealPlan, MealPlan.breakfast);
      expect(offer.occupancy.children, <int>[6]);
    });

    test('derives a deterministic offer id so carts de-duplicate', () {
      final String a =
          SynxisOfferDto.fromJson(_offerJson(), 'H-PAR-001').offerId;
      final String b =
          SynxisOfferDto.fromJson(_offerJson(), 'H-PAR-001').offerId;
      expect(a, b);
      expect(a, 'H-PAR-001:DLX:BARBB:2026-11-12');
    });

    test('non-refundable rates carry the non-refundable policy', () {
      final RoomOffer offer =
          SynxisOfferDto.fromJson(_offerJson(refundable: false), 'H-PAR-001')
              .toDomain();
      expect(offer.cancellationPolicy.isNonRefundable, isTrue);
      expect(offer.cancellationPolicy.isFreeCancellation, isFalse);
      expect(offer.cancellationPolicy.shortLabel, 'Non-refundable');
    });

    test('member rates expose the saving against the public total', () {
      final RoomOffer offer =
          SynxisOfferDto.fromJson(_offerJson(memberRate: true), 'H-PAR-001')
              .toDomain();
      expect(offer.isMemberRate, isTrue);
      expect(offer.savings, isNotNull);
      expect(offer.savings!.minorUnits, 78000 - 68400);
    });

    test('flags low inventory', () {
      final RoomOffer offer =
          SynxisOfferDto.fromJson(_offerJson(), 'H-PAR-001').toDomain();
      expect(offer.isLastRooms, isTrue);
    });

    test('a missing required field fails as a ContractFailure naming it', () {
      final Map<String, Object?> broken = _offerJson()..remove('RatePlanCode');
      expect(
        () => SynxisOfferDto.fromJson(broken, 'H-PAR-001'),
        throwsA(
          isA<ContractFailure>().having(
            (ContractFailure f) => f.field,
            'field',
            'RatePlanCode',
          ),
        ),
      );
    });
  });

  group('SynxisAvailabilityDto', () {
    test('groups offers by hotel and surfaces warnings', () {
      final SynxisAvailabilityDto dto =
          SynxisAvailabilityDto.fromJson(<String, Object?>{
        'HotelAvailability': <Object?>[
          <String, Object?>{
            'HotelId': 'H-PAR-001',
            'Offers': <Object?>[_offerJson()],
          },
          <String, Object?>{
            'HotelId': 'H-KYO-001',
            'Offers': <Object?>[_offerJson(), _offerJson(refundable: false)],
          },
        ],
        'Warnings': <Object?>['Restricted rate hidden'],
      });

      expect(dto.offersByHotelId.keys,
          containsAll(<String>['H-PAR-001', 'H-KYO-001']));
      expect(dto.offersByHotelId['H-KYO-001']!.length, 2);
      expect(dto.warnings.single, 'Restricted rate hidden');
    });
  });

  group('SynxisReservationRequest', () {
    test('sends the quote token and expected total so the CRS can re-price',
        () {
      final RoomOffer offer =
          SynxisOfferDto.fromJson(_offerJson(), 'H-PAR-001').toDomain();
      final Map<String, Object?> json = SynxisReservationRequest(
        hotelId: 'H-PAR-001',
        offer: offer,
        guest: const GuestDetails(
          firstName: 'Amara',
          lastName: 'Okonkwo',
          email: 'amara@example.com',
          phone: '+2348012345678',
        ),
        paymentIntentId: 'pi_123',
        membershipNumber: 'LS-100042',
        pointsRedeemed: 2000,
      ).toJson(chainId: '12345');

      final Map<String, Object?> roomStay =
          json['RoomStay']! as Map<String, Object?>;
      expect(roomStay['QuoteToken'], 'qt_abc');
      expect(roomStay['ExpectedTotal'], 684.0);
      final Map<String, Object?> loyalty =
          json['Loyalty']! as Map<String, Object?>;
      expect(loyalty['MembershipNumber'], 'LS-100042');
      expect(loyalty['PointsRedeemed'], 2000);
      // The CRS must never receive card data.
      final Map<String, Object?> payment =
          json['Payment']! as Map<String, Object?>;
      expect(payment.keys, <String>['IntentId', 'Type']);
    });
  });
}
