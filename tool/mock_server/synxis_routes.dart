import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'fixtures.dart';
import 'support.dart';

/// Mock **Sabre SynXis** central reservation system.
///
/// Implements the subset the app uses: hotel directory, availability shopping,
/// re-quote, reservation create/read/cancel. Prices are deterministic per
/// (property, room type, rate plan, date) so tests can assert on exact totals,
/// with a small weekend uplift so a stay spanning a Saturday costs more - which
/// is what makes the "nightly rates, not an average" modelling matter.
Router synxisRouter() {
  final Router router = Router();
  final Map<String, Map<String, Object?>> reservations =
      <String, Map<String, Object?>>{};

  router.get('/v1/api/hotels', (Request request) {
    final String? destination = request.url.queryParameters['destination'];
    final Iterable<MockHotel> hotels = mockHotels.where(
      (MockHotel h) =>
          destination == null ||
          destination == 'any' ||
          h.destinationId == destination,
    );
    return jsonResponse(<String, Object?>{
      'Hotels': hotels
          .map(
            (MockHotel h) => <String, Object?>{
              'HotelId': h.id,
              'ChainId': '12345',
              'HotelName': h.name,
              'City': h.city,
              'CountryCode': h.country,
              'Rating': h.stars,
              'Address': h.address,
              'Latitude': h.latitude,
              'Longitude': h.longitude,
              'Currency': h.currency,
              'BrandCode': 'LUXE',
            },
          )
          .toList(),
    });
  });

  router.get('/v1/api/hotels/<hotelId>/rooms',
      (Request request, String hotelId) {
    return jsonResponse(<String, Object?>{
      'RoomTypes': mockRoomTypes
          .map(
            (MockRoomType r) => <String, Object?>{
              'RoomTypeCode': r.code,
              'RoomTypeName': r.name,
              'Description': r.description,
              'MaxOccupancy': r.maxOccupancy,
              'SizeSqm': r.sizeSqm,
              'Bedding': r.bedding,
              'MediaIds': <String>['$hotelId-${r.code}-1'],
            },
          )
          .toList(),
    });
  });

  router.post('/v1/api/availability', (Request request) async {
    final Map<String, Object?> body = await readJson(request);
    final Map<String, Object?> stay =
        (body['Stay'] as Map<String, Object?>?) ?? <String, Object?>{};
    final Map<String, Object?> occupancy =
        (body['Occupancy'] as Map<String, Object?>?) ?? <String, Object?>{};
    final List<Object?> requestedIds =
        (body['HotelIds'] as List<Object?>?) ?? <Object?>[];
    final String? membershipNumber = body['MembershipNumber'] as String?;
    final String currency = (body['Currency'] as String?) ?? 'USD';
    final String? promotionCode = body['PromotionCode'] as String?;

    final DateTime arrival = parseDate(stay['Arrival'] as String?);
    final DateTime departure = parseDate(
      stay['Departure'] as String?,
      fallback: arrival.add(const Duration(days: 2)),
    );
    final int nights =
        departure.difference(arrival).inDays.clamp(1, 30).toInt();
    final int adults = (occupancy['Adults'] as num?)?.toInt() ?? 2;
    final List<int> childAges =
        ((occupancy['ChildAges'] as List<Object?>?) ?? <Object?>[])
            .map((Object? e) => (e as num?)?.toInt() ?? 8)
            .toList();

    final List<Map<String, Object?>> availability = <Map<String, Object?>>[];

    for (final MockHotel hotel in mockHotels) {
      if (requestedIds.isNotEmpty && !requestedIds.contains(hotel.id)) {
        continue;
      }
      // One property is deliberately sold out for stays starting on a Monday,
      // so the "no availability" path is reachable without editing fixtures.
      if (hotel.id == 'H-CPT-002' && arrival.weekday == DateTime.monday) {
        continue;
      }

      final List<Map<String, Object?>> offers = <Map<String, Object?>>[];
      for (final MockRoomType room in mockRoomTypes) {
        for (final MockRatePlan plan in mockRatePlans) {
          if (plan.memberOnly && membershipNumber == null) {
            continue;
          }
          final List<Map<String, Object?>> nightly = <Map<String, Object?>>[];
          int roomSubtotal = 0;
          for (int i = 0; i < nights; i++) {
            final DateTime date = arrival.add(Duration(days: i));
            final bool weekend = date.weekday == DateTime.friday ||
                date.weekday == DateTime.saturday;
            int amount = (hotel.baseNightlyMinor *
                    room.priceFactor *
                    plan.multiplier *
                    (weekend ? 1.18 : 1.0))
                .round();
            if (promotionCode == 'STAY4' && i == 3) {
              amount = 0; // fourth night free
            }
            if (promotionCode == 'SUITE25' && room.code != 'DLX') {
              amount = (amount * 0.75).round();
            }
            roomSubtotal += amount;
            nightly.add(<String, Object?>{
              'Date': isoDate(date),
              'Amount': amount / 100,
            });
          }

          final int taxes = (roomSubtotal * 0.14).round();
          final int publicTotal = plan.memberOnly
              ? ((roomSubtotal + taxes) / plan.multiplier).round()
              : 0;

          offers.add(<String, Object?>{
            'RoomType': <String, Object?>{
              'RoomTypeCode': room.code,
              'RoomTypeName': room.name,
              'Description': room.description,
              'MaxOccupancy': room.maxOccupancy,
              'SizeSqm': room.sizeSqm,
              'Bedding': room.bedding,
              'MediaIds': <String>['${hotel.id}-${room.code}-1'],
            },
            'RatePlanCode': plan.code,
            'RatePlanName': plan.name,
            'Currency': currency == 'USD' ? hotel.currency : currency,
            'NightlyRates': nightly,
            'TaxesAndFees': taxes / 100,
            'Arrival': isoDate(arrival),
            'Departure': isoDate(departure),
            'Adults': adults,
            'ChildAges': childAges,
            'QuoteToken':
                'qt_${hotel.id}_${room.code}_${plan.code}_${isoDate(arrival)}',
            'MealPlanCode': plan.mealPlanCode,
            'IsMemberRate': plan.memberOnly,
            'IsRefundable': plan.refundable,
            'CancelByUtc': plan.refundable
                ? arrival
                    .subtract(const Duration(days: 2))
                    .toUtc()
                    .toIso8601String()
                : null,
            'CancellationText': plan.refundable
                ? 'Cancel free of charge until 48 hours before arrival.'
                : 'Non-refundable.',
            'RoomsRemaining': room.code == 'STE' ? 2 : 8,
            'Inclusions': plan.inclusions,
            if (publicTotal > 0) 'PublicTotal': publicTotal / 100,
          });
        }
      }

      availability.add(<String, Object?>{
        'HotelId': hotel.id,
        'Offers': offers,
      });
    }

    return jsonResponse(<String, Object?>{
      'HotelAvailability': availability,
      'Warnings': promotionCode != null &&
              promotionCode != 'STAY4' &&
              promotionCode != 'SUITE25' &&
              promotionCode != 'MEMKYO'
          ? <String>['Promotion code $promotionCode was not recognised']
          : <String>[],
    });
  });

  /// Re-quote. Set `x-mock-rate-change: 1` to simulate the price moving between
  /// the search and the booking - the single most important unhappy path in a
  /// hotel booking flow.
  router.post('/v1/api/availability/requote', (Request request) async {
    final Map<String, Object?> body = await readJson(request);
    final String token = (body['QuoteToken'] as String?) ?? '';
    final String hotelId = (body['HotelId'] as String?) ?? '';
    final List<String> parts = token.split('_');
    if (parts.length < 5) {
      return jsonResponse(
        <String, Object?>{
          'Errors': <Map<String, String>>[
            <String, String>{
              'Code': 'INVALID_QUOTE_TOKEN',
              'Message': 'Quote token is not recognised',
            },
          ],
        },
        status: 400,
      );
    }

    final MockHotel hotel = mockHotels.firstWhere(
      (MockHotel h) => h.id == hotelId,
      orElse: () => mockHotels.first,
    );
    final MockRoomType room = mockRoomTypes.firstWhere(
      (MockRoomType r) => r.code == parts[2],
      orElse: () => mockRoomTypes.first,
    );
    final MockRatePlan plan = mockRatePlans.firstWhere(
      (MockRatePlan p) => p.code == parts[3],
      orElse: () => mockRatePlans.first,
    );
    final DateTime arrival = parseDate(parts[4]);
    final bool forceChange = request.headers['x-mock-rate-change'] == '1';
    final double drift = forceChange ? 1.09 : 1.0;

    // Mirror the availability maths so a clean re-quote returns an identical
    // total and the app proceeds without prompting the guest.
    const int nights = 2;
    final List<Map<String, Object?>> nightly = <Map<String, Object?>>[];
    int subtotal = 0;
    for (int i = 0; i < nights; i++) {
      final DateTime date = arrival.add(Duration(days: i));
      final bool weekend =
          date.weekday == DateTime.friday || date.weekday == DateTime.saturday;
      final int amount = (hotel.baseNightlyMinor *
              room.priceFactor *
              plan.multiplier *
              (weekend ? 1.18 : 1.0) *
              drift)
          .round();
      subtotal += amount;
      nightly.add(<String, Object?>{
        'Date': isoDate(date),
        'Amount': amount / 100,
      });
    }

    return jsonResponse(<String, Object?>{
      'Offer': <String, Object?>{
        'RoomType': <String, Object?>{
          'RoomTypeCode': room.code,
          'RoomTypeName': room.name,
          'Description': room.description,
          'MaxOccupancy': room.maxOccupancy,
          'SizeSqm': room.sizeSqm,
          'Bedding': room.bedding,
        },
        'RatePlanCode': plan.code,
        'RatePlanName': plan.name,
        'Currency': hotel.currency,
        'NightlyRates': nightly,
        'TaxesAndFees': (subtotal * 0.14).round() / 100,
        'Arrival': isoDate(arrival),
        'Departure': isoDate(arrival.add(const Duration(days: nights))),
        'Adults': 2,
        'ChildAges': <int>[],
        'QuoteToken': token,
        'MealPlanCode': plan.mealPlanCode,
        'IsMemberRate': plan.memberOnly,
        'IsRefundable': plan.refundable,
      },
    });
  });

  router.post('/v1/api/reservations', (Request request) async {
    final String? key = request.headers['idempotency-key'];
    final Object? replay = idempotency.get(key);
    if (replay != null) {
      // Proof that a retried booking cannot double-book.
      return jsonResponse(replay,
          headers: <String, String>{'x-idempotent-replay': '1'});
    }

    final Map<String, Object?> body = await readJson(request);
    final String hotelId = (body['HotelId'] as String?) ?? '';
    final Map<String, Object?> roomStay =
        (body['RoomStay'] as Map<String, Object?>?) ?? <String, Object?>{};
    final Map<String, Object?> guest =
        (body['Guest'] as Map<String, Object?>?) ?? <String, Object?>{};
    final MockHotel hotel = mockHotels.firstWhere(
      (MockHotel h) => h.id == hotelId,
      orElse: () => mockHotels.first,
    );

    final String confirmation = reference('LX');
    final Map<String, Object?> payload = <String, Object?>{
      'Reservation': <String, Object?>{
        'ConfirmationNumber': confirmation,
        'CrsReservationId': 'crs_${confirmation.toLowerCase()}',
        'HotelId': hotel.id,
        'HotelName': hotel.name,
        'Status': 'Confirmed',
        'Total': (roomStay['ExpectedTotal'] as num?) ?? 0,
        'Currency': (roomStay['Currency'] as String?) ?? hotel.currency,
        'CreatedUtc': DateTime.now().toUtc().toIso8601String(),
        'ItineraryUrl':
            '${originOf(request)}/cms/pages/itinerary?ref=$confirmation',
        'PaymentLast4': '4242',
        'GuestLastName': guest['LastName'],
      },
    };
    reservations[confirmation] =
        payload['Reservation']! as Map<String, Object?>;
    idempotency.put(key, payload);
    return jsonResponse(payload, status: 201);
  });

  router.get('/v1/api/reservations/<confirmation>',
      (Request request, String confirmation) {
    final Map<String, Object?>? found = reservations[confirmation];
    if (found == null) {
      return jsonResponse(
        <String, Object?>{
          'Errors': <Map<String, String>>[
            <String, String>{
              'Code': 'RESERVATION_NOT_FOUND',
              'Message': 'No reservation for $confirmation',
            },
          ],
        },
        status: 404,
      );
    }
    return jsonResponse(<String, Object?>{'Reservation': found});
  });

  router.post('/v1/api/reservations/<confirmation>/cancel',
      (Request request, String confirmation) {
    final Map<String, Object?>? found = reservations[confirmation];
    if (found == null) {
      return jsonResponse(<String, Object?>{'Status': 'NotFound'}, status: 404);
    }
    found['Status'] = 'Cancelled';
    return jsonResponse(<String, Object?>{'Status': 'Cancelled'});
  });

  return router;
}
