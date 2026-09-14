import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/result.dart';
import '../../core/utils/date_x.dart';
import '../../domain/search.dart';
import 'synxis_models.dart';

/// Transport for Sabre **SynXis** - the central reservation system that owns
/// inventory, rates and reservations for the 400+ properties in the programme.
///
/// Scope of this class: build the request, hand the raw JSON to a mapper, return
/// a [Result]. No domain logic, no caching, no UI concerns. That separation is
/// what makes the SynXis contract swappable - if the chain migrates to another
/// CRS, `SynxisApi` + `SynxisMappers` is the blast radius.
///
/// ### Wire format
/// These endpoints and PascalCase payloads are LuxeStays demo BFF assumptions.
/// They are NOT the public SynXis Property Hub Reservation API. That API has a
/// separately documented retrieval contract, implemented by property_hub_routes.
/// Never point this client at a real SynXis origin. See docs/15-API-AUDIT.md.
class SynxisApi {
  SynxisApi({required this._client, required this._chainId});

  final ApiClient _client;
  final String _chainId;

  /// Property search. In SynXis terms: the chain's hotel directory, filtered
  /// by destination. Cheap and cacheable - it does not price anything.
  Future<Result<List<SynxisHotelDto>>> searchHotels({
    required Destination destination,
    CancelToken? cancelToken,
  }) {
    return _client.getJson<List<SynxisHotelDto>>(
      '/v1/api/hotels',
      query: <String, Object?>{
        'chainId': _chainId,
        if (destination.type != DestinationType.anywhere)
          'destination': destination.id,
        if (destination.latitude != null) 'latitude': destination.latitude,
        if (destination.longitude != null) 'longitude': destination.longitude,
      },
      cancelToken: cancelToken,
      decode: (Object? json) {
        final Map<String, Object?> root = JsonRead.object(json, 'root');
        return JsonRead.objectList(
          root['Hotels'],
          'Hotels',
        ).map(SynxisHotelDto.fromJson).toList(growable: false);
      },
    );
  }

  /// Availability + pricing for a stay.
  ///
  /// This is the expensive call: the CRS prices every rate plan for every
  /// requested property, per night. It is POSTed (not GET) because the request
  /// carries child ages and rate-access codes, and because this demo models it as
  /// a shopping transaction rather than a cacheable resource.
  Future<Result<SynxisAvailabilityDto>> availability({
    required List<String> hotelIds,
    required SearchQuery query,
    String? membershipNumber,
    CancelToken? cancelToken,
  }) {
    return _client.postJson<SynxisAvailabilityDto>(
      '/v1/api/availability',
      cancelToken: cancelToken,
      body: <String, Object?>{
        'ChainId': _chainId,
        'HotelIds': hotelIds,
        'Stay': <String, Object?>{
          'Arrival': query.stay.checkIn.iso8601Date,
          'Departure': query.stay.checkOut.iso8601Date,
        },
        'Occupancy': <String, Object?>{
          'Adults': query.occupancy.adults,
          'ChildAges': query.occupancy.children,
          'Rooms': query.occupancy.rooms,
        },
        'Currency': query.currency,
        if (query.promotionCode != null) 'PromotionCode': query.promotionCode,
        if (query.corporateCode != null) 'CorporateCode': query.corporateCode,
        // Passing the membership number is what makes SynXis return the
        // member-only rate plans alongside the public ones.
        'MembershipNumber': ?membershipNumber,
        'RatePlanFilter': <String, Object?>{
          'RefundableOnly': query.filters.freeCancellationOnly,
          'MemberOnly': query.filters.memberRatesOnly,
        },
      },
      decode: (Object? json) =>
          SynxisAvailabilityDto.fromJson(JsonRead.object(json, 'root')),
    );
  }

  /// Re-price a single offer immediately before payment.
  ///
  /// Hotel inventory is perishable and rates move. Booking against a quote the
  /// guest saw twenty minutes ago is how you get a price-mismatch chargeback,
  /// so checkout always re-quotes first and compares totals.
  Future<Result<SynxisOfferDto>> requote({
    required String hotelId,
    required String offerToken,
    CancelToken? cancelToken,
  }) {
    return _client.postJson<SynxisOfferDto>(
      '/v1/api/availability/requote',
      cancelToken: cancelToken,
      body: <String, Object?>{
        'ChainId': _chainId,
        'HotelId': hotelId,
        'QuoteToken': offerToken,
      },
      decode: (Object? json) {
        final Map<String, Object?> root = JsonRead.object(json, 'root');
        return SynxisOfferDto.fromJson(
          JsonRead.object(root['Offer'], 'Offer'),
          hotelId,
        );
      },
    );
  }

  /// Creates a reservation.
  ///
  /// Non-idempotent by nature, so it always carries an `Idempotency-Key`
  /// derived from the cart id + revision (`Ids.idempotencyKeyFor`). That single
  /// header is what allows `RetryInterceptor` to replay a timed-out booking
  /// without the guest being charged twice.
  Future<Result<SynxisReservationDto>> createReservation({
    required SynxisReservationRequest request,
    required String idempotencyKey,
    CancelToken? cancelToken,
  }) {
    return _client.postJson<SynxisReservationDto>(
      '/v1/api/reservations',
      idempotencyKey: idempotencyKey,
      cancelToken: cancelToken,
      body: request.toJson(chainId: _chainId),
      decode: (Object? json) {
        final Map<String, Object?> root = JsonRead.object(json, 'root');
        return SynxisReservationDto.fromJson(
          JsonRead.object(root['Reservation'], 'Reservation'),
        );
      },
    );
  }

  Future<Result<SynxisReservationDto>> reservation(
    String confirmationNumber, {
    String? lastName,
    CancelToken? cancelToken,
  }) {
    return _client.getJson<SynxisReservationDto>(
      '/v1/api/reservations/$confirmationNumber',
      query: <String, Object?>{'chainId': _chainId, 'lastName': ?lastName},
      cancelToken: cancelToken,
      decode: (Object? json) {
        final Map<String, Object?> root = JsonRead.object(json, 'root');
        return SynxisReservationDto.fromJson(
          JsonRead.object(root['Reservation'], 'Reservation'),
        );
      },
    );
  }

  Future<Result<bool>> cancelReservation(
    String confirmationNumber, {
    required String reason,
    CancelToken? cancelToken,
  }) {
    return _client.postJson<bool>(
      '/v1/api/reservations/$confirmationNumber/cancel',
      idempotencyKey: 'cancel_$confirmationNumber',
      cancelToken: cancelToken,
      body: <String, Object?>{'ChainId': _chainId, 'Reason': reason},
      decode: (Object? json) {
        final Map<String, Object?> root = JsonRead.object(json, 'root');
        return JsonRead.stringOrNull(root, 'Status') == 'Cancelled';
      },
    );
  }

  /// Room types for a property (descriptions, bedding, occupancy limits).
  Future<Result<List<SynxisRoomTypeDto>>> roomTypes(
    String hotelId, {
    CancelToken? cancelToken,
  }) {
    return _client.getJson<List<SynxisRoomTypeDto>>(
      '/v1/api/hotels/$hotelId/rooms',
      query: <String, Object?>{'chainId': _chainId},
      cancelToken: cancelToken,
      decode: (Object? json) {
        final Map<String, Object?> root = JsonRead.object(json, 'root');
        return JsonRead.objectList(
          root['RoomTypes'],
          'RoomTypes',
        ).map(SynxisRoomTypeDto.fromJson).toList(growable: false);
      },
    );
  }
}
