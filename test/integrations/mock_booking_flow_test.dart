import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luxe_stays/integrations/synxis/synxis_models.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../tool/mock_server/payment_routes.dart';
import '../../tool/mock_server/property_hub_routes.dart';
import '../../tool/mock_server/salesforce_routes.dart';
import '../../tool/mock_server/support.dart';
import '../../tool/mock_server/synxis_routes.dart';

void main() {
  late Handler handler;
  setUp(() {
    paymentIntents.clear();
    final Router root = Router()
      ..mount('/synxis/', synxisRouter().call)
      ..mount('/payments/', paymentRouter().call)
      ..mount('/salesforce/', salesforceRouter().call)
      ..mount('/v1/sph/', propertyHubRouter().call);
    handler = chaosMiddleware()(root.call);
  });

  Future<Response> request(
    String method,
    String path, {
    Object? body,
    Map<String, String> headers = const {},
  }) async => handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: {'content-type': 'application/json', ...headers},
      body: body == null ? null : jsonEncode(body),
    ),
  );
  Future<Map<String, Object?>> json(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, Object?>;
  Map<String, Object?> search({int nights = 4}) => {
    'HotelIds': ['H-PAR-001'],
    'Currency': 'USD',
    'ChainId': '12345',
    'Stay': {'Arrival': '2027-01-15', 'Departure': '2027-01-${15 + nights}'},
    'Occupancy': {'Adults': 2, 'ChildAges': <int>[], 'Rooms': 1},
    'PromotionCode': 'STAY4',
  };

  test(
    'payment validation, replay conflicts and void are observable',
    () async {
      final body = {
        'amountMinor': 10000,
        'currency': 'USD',
        'cartId': 'validation',
      };
      expect(
        (await request(
          'POST',
          '/payments/intents',
          body: {...body, 'amountMinor': -1},
        )).statusCode,
        422,
      );
      final payload = await json(
        await request(
          'POST',
          '/payments/intents',
          body: body,
          headers: {'idempotency-key': 'payment-validation'},
        ),
      );
      expect(
        (await request(
          'POST',
          '/payments/intents',
          body: {...body, 'amountMinor': 20000},
          headers: {'idempotency-key': 'payment-validation'},
        )).statusCode,
        409,
      );
      final id = payload['intentId'];
      await request(
        'POST',
        '/payments/intents/$id/authorize',
        body: {'outcome': 'authorize'},
      );
      expect(
        (await json(
          await request('POST', '/payments/intents/$id/void'),
        ))['status'],
        'cancelled',
      );
      expect(
        (await json(await request('GET', '/payments/intents/$id')))['status'],
        'cancelled',
      );
    },
  );

  test('loyalty rejects negative redemption and unknown members', () async {
    const path =
        '/salesforce/services/data/v62.0/connect/loyalty/programs/LuxeStaysRewards/program-processes/RedeemPointsForVoucher';
    expect(
      (await request(
        'POST',
        path,
        body: {
          'processParameters': [
            {'MembershipNumber': 'LS-100042', 'Points': -100},
          ],
        },
      )).statusCode,
      400,
    );
    expect(
      (await request(
        'POST',
        path,
        body: {
          'processParameters': [
            {'MembershipNumber': 'missing', 'Points': 100},
          ],
        },
      )).statusCode,
      404,
    );
  });

  test(
    'four-night promotional search, re-quote, payment, book, retrieve, cancel',
    () async {
      final Response searched = await request(
        'POST',
        '/synxis/v1/api/availability',
        body: search(),
      );
      expect(searched.statusCode, 200);
      final SynxisAvailabilityDto availability = SynxisAvailabilityDto.fromJson(
        await json(searched),
      );
      final SynxisOfferDto offer =
          availability.offersByHotelId['H-PAR-001']!.first;
      expect(offer.nightlyRates.length, 4);
      expect(offer.nightlyRates.values.last, 0);
      final Map<String, Object?> repriced = await json(
        await request(
          'POST',
          '/synxis/v1/api/availability/requote',
          body: {'HotelId': offer.hotelId, 'QuoteToken': offer.quoteToken},
        ),
      );
      final SynxisOfferDto fresh = SynxisOfferDto.fromJson(
        repriced['Offer']! as Map<String, Object?>,
        offer.hotelId,
      );
      expect(fresh.toDomain().total, offer.toDomain().total);
      expect(fresh.departure, offer.departure);

      final Map<String, Object?> intent = await json(
        await request(
          'POST',
          '/payments/intents',
          body: {
            'amountMinor': offer.toDomain().total.minorUnits,
            'currency': 'USD',
            'cartId': 'flow',
          },
          headers: {'idempotency-key': 'flow-payment'},
        ),
      );
      final String id = intent['intentId']! as String;
      final Map<String, Object?> booking = {
        'HotelId': offer.hotelId,
        'RoomStay': {
          'QuoteToken': offer.quoteToken,
          'ExpectedTotal': offer.toDomain().total.asDouble,
          'Currency': 'USD',
        },
        'Guest': {
          'FirstName': 'Ada',
          'LastName': 'Guest',
          'Email': 'ada@example.test',
        },
        'Payment': {'IntentId': id},
      };
      expect(
        (await request(
          'POST',
          '/synxis/v1/api/reservations',
          body: booking,
          headers: {'idempotency-key': 'reservation-flow'},
        )).statusCode,
        403,
      );
      expect(
        (await request(
          'POST',
          '/payments/intents/$id/authorize',
          body: {'outcome': 'authorize'},
        )).statusCode,
        200,
      );
      final Response created = await request(
        'POST',
        '/synxis/v1/api/reservations',
        body: booking,
        headers: {'idempotency-key': 'reservation-flow'},
      );
      expect(created.statusCode, 201);
      final Map<String, Object?> payload = await json(created);
      final SynxisReservationDto reservation = SynxisReservationDto.fromJson(
        payload['Reservation']! as Map<String, Object?>,
      );
      final Response replay = await request(
        'POST',
        '/synxis/v1/api/reservations',
        body: booking,
        headers: {'idempotency-key': 'reservation-flow'},
      );
      expect(await json(replay), payload);
      expect(replay.headers['x-idempotent-replay'], '1');
      expect(
        (await request(
          'POST',
          '/synxis/v1/api/reservations',
          body: {...booking, 'HotelId': 'other'},
          headers: {'idempotency-key': 'reservation-flow'},
        )).statusCode,
        409,
      );
      final String path =
          '/synxis/v1/api/reservations/${reservation.confirmationNumber}';
      expect((await request('GET', '$path?lastName=wrong')).statusCode, 403);
      expect((await request('GET', '$path?lastName=Guest')).statusCode, 200);
      expect((await request('POST', '$path/cancel')).statusCode, 200);
      final Map<String, Object?> cancelled = await json(
        await request('GET', path),
      );
      expect(
        (cancelled['Reservation']! as Map<String, Object?>)['Status'],
        'Cancelled',
      );
    },
  );

  test(
    'validation, empty inventory, missing quote and deterministic failures',
    () async {
      expect(
        (await request(
          'POST',
          '/synxis/v1/api/availability',
          body: search(nights: 0),
        )).statusCode,
        422,
      );
      expect(
        (await request(
          'POST',
          '/synxis/v1/api/availability',
          body: <Object?>[],
        )).statusCode,
        400,
      );
      expect(
        (await request(
          'POST',
          '/synxis/v1/api/availability',
          body: {...search(), 'Stay': 12},
        )).statusCode,
        422,
      );
      final Map<String, Object?> empty = await json(
        await request(
          'POST',
          '/synxis/v1/api/availability',
          body: {
            ...search(),
            'HotelIds': ['missing'],
          },
        ),
      );
      expect(empty['HotelAvailability'], isEmpty);
      expect(
        (await request(
          'POST',
          '/synxis/v1/api/availability/requote',
          body: {'QuoteToken': 'invented'},
        )).statusCode,
        400,
      );
      for (final int status in [401, 403, 503]) {
        expect(
          (await request(
            'GET',
            '/synxis/v1/api/hotels',
            headers: {'x-mock-fail': '$status'},
          )).statusCode,
          status,
        );
      }
      expect(
        (await request('OPTIONS', '/synxis/v1/api/hotels')).statusCode,
        200,
      );
    },
  );

  test(
    'Property Hub documented retrieval uses tenantId and lower camelCase',
    () async {
      const String path =
          '/v1/sph/reservations/outbound/data/reservations-details';
      final Map<String, Object?> body = {
        'hotelId': 1234,
        'chainId': 12345,
        'client': 'DEMO',
        'startDateTime': '2027-01-01T00:00:00Z',
        'endDateTime': '2027-01-02T00:00:00Z',
        'delta': false,
        'updateDelta': false,
      };
      expect((await request('POST', path, body: body)).statusCode, 400);
      final Map<String, Object?> result = await json(
        await request('POST', path, body: body, headers: {'tenantId': '1'}),
      );
      expect(result['status'], 'SUCCESS');
      expect(result['total'], 1);
      expect(result.containsKey('Reservation'), isFalse);
      expect(
        (await request('POST', '/v1/sph/reservations', body: body)).statusCode,
        404,
      );
    },
  );
}
