import '../../core/error/failure.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result.dart';
import '../../core/utils/money.dart';
import '../../domain/booking.dart';
import '../../domain/hotel.dart';
import '../../domain/rate.dart';
import '../../domain/search.dart';
import 'synxis_api.dart';
import 'synxis_models.dart';

/// Domain-facing SynXis operations.
///
/// Adds the behaviour that the transport layer must not own:
///  * DTO → domain mapping;
///  * a short-lived availability cache (the CRS charges per shop request and
///    rate-limits hard, so re-searching the same query within the window is
///    served from memory);
///  * the re-quote-then-book guard that protects against price drift.
class SynxisRepository {
  SynxisRepository({
    required this._api,
    required this._logger,
    this.availabilityTtl = const Duration(minutes: 5),
  });

  final SynxisApi _api;
  final AppLogger _logger;
  final Duration availabilityTtl;

  final Map<String, _CachedAvailability> _availabilityCache =
      <String, _CachedAvailability>{};

  Future<Result<List<Hotel>>> hotels(Destination destination) async {
    final Result<List<SynxisHotelDto>> result = await _api.searchHotels(
      destination: destination,
    );
    return result.map(
      (List<SynxisHotelDto> dtos) => dtos
          .map(
            (SynxisHotelDto dto) => Hotel(
              id: dto.hotelId,
              chainId: dto.chainId,
              name: dto.name,
              city: dto.city,
              country: dto.countryCode,
              starRating: dto.starRating,
              latitude: dto.latitude,
              longitude: dto.longitude,
              address: dto.address,
            ),
          )
          .toList(growable: false),
    );
  }

  /// Availability for a set of properties, memoised per [SearchQuery.cacheKey].
  Future<Result<Map<String, List<RoomOffer>>>> availability({
    required List<String> hotelIds,
    required SearchQuery query,
    String? membershipNumber,
    bool forceRefresh = false,
  }) async {
    final String key =
        '${query.cacheKey}#${(hotelIds.toList()..sort()).join(',')}'
        '#${membershipNumber ?? '-'}';
    final _CachedAvailability? cached = _availabilityCache[key];
    if (!forceRefresh && cached != null && !cached.isStale(availabilityTtl)) {
      _logger.debug(
        'availability cache hit',
        context: <String, Object?>{
          'key': key,
          'ageMs': DateTime.now().difference(cached.at).inMilliseconds,
        },
      );
      return Ok<Map<String, List<RoomOffer>>>(cached.offers);
    }

    final Result<SynxisAvailabilityDto> result = await _api.availability(
      hotelIds: hotelIds,
      query: query,
      membershipNumber: membershipNumber,
    );

    return result.map((SynxisAvailabilityDto dto) {
      if (dto.warnings.isNotEmpty) {
        _logger.warn(
          'SynXis availability warnings',
          context: <String, Object?>{'warnings': dto.warnings},
        );
      }
      final Map<String, List<RoomOffer>> offers = dto.offersByHotelId.map((
        String hotelId,
        List<SynxisOfferDto> list,
      ) {
        return MapEntry<String, List<RoomOffer>>(
          hotelId,
          list.map((SynxisOfferDto o) => o.toDomain()).toList(growable: false),
        );
      });
      _availabilityCache[key] = _CachedAvailability(
        offers: offers,
        at: DateTime.now(),
      );
      return offers;
    });
  }

  /// Re-prices [offer] and fails loudly if the total moved.
  ///
  /// Returning a [RateChangedFailure] rather than silently accepting the new
  /// price is a deliberate product decision: the guest must confirm any change
  /// before we take their money.
  Future<Result<RoomOffer>> revalidate(RoomOffer offer) async {
    final String? token = offer.quoteToken;
    if (token == null) {
      // No token means the offer was never quoted by the CRS (e.g. it came
      // from a cached search that predates a contract change). Treat it as
      // stale rather than trusting it.
      return Err<RoomOffer>(
        ClientFailure(
          userMessage: 'Please search again to get an up-to-date price.',
          developerMessage: 'offer ${offer.offerId} has no quote token',
          statusCode: 0,
        ),
      );
    }

    final Result<SynxisOfferDto> result = await _api.requote(
      hotelId: offer.hotelId,
      offerToken: token,
    );

    return result.fold<Result<RoomOffer>>((SynxisOfferDto dto) {
      final RoomOffer fresh = dto.toDomain();
      if (fresh.total != offer.total) {
        _logger.warn(
          'rate drift detected',
          context: <String, Object?>{
            'offerId': offer.offerId,
            'was': offer.total.minorUnits,
            'now': fresh.total.minorUnits,
          },
        );
        return Err<RoomOffer>(
          RateChangedFailure(
            developerMessage: 'rate changed for ${offer.offerId}',
            previousTotalMinor: offer.total.minorUnits,
            currentTotalMinor: fresh.total.minorUnits,
            currency: fresh.total.currency,
          ),
        );
      }
      return Ok<RoomOffer>(fresh);
    }, Err<RoomOffer>.new);
  }

  Future<Result<Reservation>> book({
    required RoomOffer offer,
    required GuestDetails guest,
    required String hotelName,
    required String paymentIntentId,
    required String idempotencyKey,
    String? membershipNumber,
    int pointsRedeemed = 0,
    String? voucherCode,
  }) async {
    final Result<SynxisReservationDto> result = await _api.createReservation(
      idempotencyKey: idempotencyKey,
      request: SynxisReservationRequest(
        hotelId: offer.hotelId,
        offer: offer,
        guest: guest,
        paymentIntentId: paymentIntentId,
        membershipNumber: membershipNumber,
        pointsRedeemed: pointsRedeemed,
        voucherCode: voucherCode,
      ),
    );

    return result.map(
      (SynxisReservationDto dto) => Reservation(
        confirmationNumber: dto.confirmationNumber,
        crsReservationId: dto.crsReservationId,
        hotelId: dto.hotelId,
        hotelName: dto.hotelName.isEmpty ? hotelName : dto.hotelName,
        offer: offer,
        guest: guest,
        total: Money(dto.totalMinor, dto.currency),
        createdAt: dto.createdAt,
        status: dto.domainStatus,
        pointsRedeemed: pointsRedeemed,
        paymentLast4: dto.paymentLast4,
        itineraryUrl: dto.itineraryUrl,
      ),
    );
  }

  Future<Result<bool>> cancel(String confirmationNumber, String reason) =>
      _api.cancelReservation(confirmationNumber, reason: reason);

  Future<Result<List<RoomType>>> roomTypes(String hotelId) async {
    final Result<List<SynxisRoomTypeDto>> result = await _api.roomTypes(
      hotelId,
    );
    return result.map(
      (List<SynxisRoomTypeDto> dtos) => dtos
          .map((SynxisRoomTypeDto d) => d.toDomain())
          .toList(growable: false),
    );
  }

  void clearCache() => _availabilityCache.clear();
}

class _CachedAvailability {
  const _CachedAvailability({required this.offers, required this.at});

  final Map<String, List<RoomOffer>> offers;
  final DateTime at;

  bool isStale(Duration ttl) => DateTime.now().difference(at) > ttl;
}
