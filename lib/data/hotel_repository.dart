import '../core/error/failure.dart';
import '../core/logging/app_logger.dart';
import '../core/result.dart';
import '../domain/hotel.dart';
import '../domain/media.dart';
import '../domain/rate.dart';
import '../domain/search.dart';
import '../integrations/cms/cms_models.dart';
import '../integrations/cms/cms_repository.dart';
import '../integrations/leonardo/media_provider.dart';
import '../integrations/synxis/synxis_repository.dart';

/// The composition root for "show me hotels".
///
/// This is where the four systems actually meet, and the ordering is the whole
/// design:
///
/// ```
/// SynXis /hotels        →  which properties exist        (required)
/// SynXis /availability  →  what they cost for this stay  (required)
/// CMS    /entries       →  what we say about them        (best effort)
/// Leonardo /media       →  what they look like           (best effort)
/// ```
///
/// The two required calls are sequential because the second needs the first's
/// ids. The two best-effort calls run **in parallel with each other** and
/// neither can fail the search: a property with no marketing copy and a grey
/// placeholder is still bookable, and bookable is the point.
class HotelRepository {
  HotelRepository({
    required SynxisRepository synxis,
    required CmsRepository cms,
    required MediaProvider media,
    required AppLogger logger,
    this.galleryPrefetchCount = 12,
  })  : _synxis = synxis,
        _cms = cms,
        _media = media,
        _logger = logger;

  final SynxisRepository _synxis;
  final CmsRepository _cms;
  final MediaProvider _media;
  final AppLogger _logger;

  /// How many result cards get their imagery prefetched. Beyond the fold there
  /// is no point paying for the round trip until the user scrolls.
  final int galleryPrefetchCount;

  Future<Result<List<HotelSearchResult>>> search(
    SearchQuery query, {
    String? membershipNumber,
    bool forceRefresh = false,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();

    final Result<List<Hotel>> hotelsResult =
        await _synxis.hotels(query.destination);
    final List<Hotel>? hotels = hotelsResult.valueOrNull;
    if (hotels == null) {
      return Err<List<HotelSearchResult>>(hotelsResult.failureOrNull!);
    }
    if (hotels.isEmpty) {
      return const Ok<List<HotelSearchResult>>(<HotelSearchResult>[]);
    }

    final List<String> hotelIds =
        hotels.map((Hotel h) => h.id).toList(growable: false);

    final Result<Map<String, List<RoomOffer>>> availabilityResult =
        await _synxis.availability(
      hotelIds: hotelIds,
      query: query,
      membershipNumber: membershipNumber,
      forceRefresh: forceRefresh,
    );
    final Map<String, List<RoomOffer>>? offersByHotel =
        availabilityResult.valueOrNull;
    if (offersByHotel == null) {
      return Err<List<HotelSearchResult>>(availabilityResult.failureOrNull!);
    }

    // Only enrich what we are actually going to show.
    final List<Hotel> available = hotels
        .where((Hotel h) =>
            (offersByHotel[h.id] ?? const <RoomOffer>[]).isNotEmpty)
        .toList(growable: false);

    final List<String> enrichIds = available
        .take(galleryPrefetchCount)
        .map((Hotel h) => h.id)
        .toList(growable: false);

    // Content and media in parallel; both best-effort.
    final Future<Map<String, CmsHotelContent>> contentFuture = _cms
        .hotelContent(available.map((Hotel h) => h.id).toList(growable: false));
    final Future<Map<String, List<MediaAsset>>> galleriesFuture =
        _galleriesFor(enrichIds);

    final Map<String, CmsHotelContent> content = await contentFuture;
    final Map<String, List<MediaAsset>> galleries = await galleriesFuture;

    final List<HotelSearchResult> results = <HotelSearchResult>[];
    for (final Hotel hotel in available) {
      final CmsHotelContent? cms = content[hotel.id];
      final List<RoomOffer> offers = offersByHotel[hotel.id]!;
      results.add(
        HotelSearchResult(
          hotel: hotel.mergeContent(
            editorial: cms?.toEditorial(),
            gallery: galleries[hotel.id],
            amenities: cms?.amenities,
            highlights: cms?.highlights,
            tags: cms?.tags,
          ),
          offers: offers,
        ),
      );
    }

    final List<HotelSearchResult> filtered =
        _applyFilters(results, query.filters);
    _sort(filtered, query.filters.sort);

    stopwatch.stop();
    _logger.info(
      'search complete',
      context: <String, Object?>{
        'destination': query.destination.id,
        'properties': hotels.length,
        'available': available.length,
        'afterFilters': filtered.length,
        'withContent': content.length,
        'ms': stopwatch.elapsedMilliseconds,
      },
    );
    return Ok<List<HotelSearchResult>>(filtered);
  }

  /// Full detail for one property: all offers, all rooms, the whole gallery.
  Future<Result<HotelDetail>> detail({
    required String hotelId,
    required SearchQuery query,
    String? membershipNumber,
  }) async {
    final Result<List<Hotel>> hotelsResult =
        await _synxis.hotels(query.destination);
    final List<Hotel> candidates = hotelsResult.valueOrNull ?? const <Hotel>[];
    Hotel? hotel;
    for (final Hotel candidate in candidates) {
      if (candidate.id == hotelId) {
        hotel = candidate;
        break;
      }
    }

    if (hotel == null) {
      return Err<HotelDetail>(
        hotelsResult.failureOrNull ??
            ClientFailure(
              userMessage: 'We could not find that property.',
              developerMessage: 'hotel $hotelId not in destination '
                  '${query.destination.id}',
              statusCode: 404,
            ),
      );
    }

    final Result<Map<String, List<RoomOffer>>> availability =
        await _synxis.availability(
      hotelIds: <String>[hotelId],
      query: query,
      membershipNumber: membershipNumber,
    );

    final Map<String, CmsHotelContent> content =
        await _cms.hotelContent(<String>[hotelId]);
    final Map<String, List<MediaAsset>> galleries =
        await _galleriesFor(<String>[hotelId]);

    final CmsHotelContent? cms = content[hotelId];
    return Ok<HotelDetail>(
      HotelDetail(
        hotel: hotel.mergeContent(
          editorial: cms?.toEditorial(),
          gallery: galleries[hotelId],
          amenities: cms?.amenities,
          highlights: cms?.highlights,
          tags: cms?.tags,
        ),
        offers: availability.valueOrNull?[hotelId] ?? const <RoomOffer>[],
        offersFailure: availability.failureOrNull?.userMessage,
      ),
    );
  }

  Future<Map<String, List<MediaAsset>>> _galleriesFor(
    List<String> hotelIds,
  ) async {
    final Map<String, List<MediaAsset>> out = <String, List<MediaAsset>>{};
    final List<Future<void>> futures = hotelIds.map((String id) async {
      final Result<List<MediaAsset>> result = await _media.galleryFor(id);
      final List<MediaAsset>? assets = result.valueOrNull;
      if (assets != null && assets.isNotEmpty) {
        out[id] = assets;
      }
    }).toList(growable: false);
    await Future.wait(futures);
    return out;
  }

  List<HotelSearchResult> _applyFilters(
    List<HotelSearchResult> results,
    SearchFilters filters,
  ) {
    if (filters.isEmpty) {
      return results;
    }
    return results
        .map((HotelSearchResult r) => r.withOffers(
              r.offers.where((RoomOffer o) => _offerMatches(o, filters)).toList(
                    growable: false,
                  ),
            ))
        .where(
          (HotelSearchResult r) =>
              r.offers.isNotEmpty &&
              r.hotel.starRating >= filters.minStars &&
              (filters.amenities.isEmpty ||
                  filters.amenities
                      .every((String a) => r.hotel.amenities.contains(a))),
        )
        .toList(growable: false);
  }

  bool _offerMatches(RoomOffer offer, SearchFilters filters) {
    final int? maxRate = filters.maxNightlyRateMinor;
    if (maxRate != null && offer.averageNightly.minorUnits > maxRate) {
      return false;
    }
    if (filters.freeCancellationOnly &&
        !offer.cancellationPolicy.isFreeCancellation) {
      return false;
    }
    if (filters.memberRatesOnly && !offer.isMemberRate) {
      return false;
    }
    if (filters.mealPlans.isNotEmpty &&
        !filters.mealPlans.contains(offer.mealPlan)) {
      return false;
    }
    return true;
  }

  void _sort(List<HotelSearchResult> results, SortOption sort) {
    switch (sort) {
      case SortOption.priceLowToHigh:
        results.sort((HotelSearchResult a, HotelSearchResult b) =>
            a.leadInTotalMinor.compareTo(b.leadInTotalMinor));
        break;
      case SortOption.priceHighToLow:
        results.sort((HotelSearchResult a, HotelSearchResult b) =>
            b.leadInTotalMinor.compareTo(a.leadInTotalMinor));
        break;
      case SortOption.starRating:
        results.sort((HotelSearchResult a, HotelSearchResult b) =>
            b.hotel.starRating.compareTo(a.hotel.starRating));
        break;
      case SortOption.guestRating:
        results.sort((HotelSearchResult a, HotelSearchResult b) =>
            (b.hotel.guestRating ?? 0).compareTo(a.hotel.guestRating ?? 0));
        break;
      case SortOption.recommended:
        // "Recommended" is a merchandising decision, not a technical one. Here
        // it is: has editorial content, then star rating, then price - which is
        // a stand-in for whatever the commercial team's real ranking is.
        results.sort((HotelSearchResult a, HotelSearchResult b) {
          final int contentRank = (b.hotel.editorial != null ? 1 : 0)
              .compareTo(a.hotel.editorial != null ? 1 : 0);
          if (contentRank != 0) {
            return contentRank;
          }
          final int stars = b.hotel.starRating.compareTo(a.hotel.starRating);
          if (stars != 0) {
            return stars;
          }
          return a.leadInTotalMinor.compareTo(b.leadInTotalMinor);
        });
        break;
    }
  }
}

class HotelSearchResult {
  const HotelSearchResult({required this.hotel, required this.offers});

  final Hotel hotel;
  final List<RoomOffer> offers;

  /// The cheapest bookable product - what the card shows as "from".
  RoomOffer? get leadInOffer {
    if (offers.isEmpty) {
      return null;
    }
    return offers.reduce(
      (RoomOffer a, RoomOffer b) =>
          a.total.minorUnits <= b.total.minorUnits ? a : b,
    );
  }

  int get leadInTotalMinor => leadInOffer?.total.minorUnits ?? 1 << 30;

  RoomOffer? get bestMemberOffer {
    final Iterable<RoomOffer> member =
        offers.where((RoomOffer o) => o.isMemberRate);
    if (member.isEmpty) {
      return null;
    }
    return member.reduce(
      (RoomOffer a, RoomOffer b) =>
          a.total.minorUnits <= b.total.minorUnits ? a : b,
    );
  }

  HotelSearchResult withOffers(List<RoomOffer> offers) =>
      HotelSearchResult(hotel: hotel, offers: offers);
}

class HotelDetail {
  const HotelDetail({
    required this.hotel,
    required this.offers,
    this.offersFailure,
  });

  final Hotel hotel;
  final List<RoomOffer> offers;

  /// Set when the property loaded but pricing did not - the screen shows the
  /// hotel with a retry affordance rather than an error page.
  final String? offersFailure;

  Map<String, List<RoomOffer>> get offersByRoomType {
    final Map<String, List<RoomOffer>> grouped = <String, List<RoomOffer>>{};
    for (final RoomOffer offer in offers) {
      grouped.putIfAbsent(offer.roomType.code, () => <RoomOffer>[]).add(offer);
    }
    for (final List<RoomOffer> list in grouped.values) {
      list.sort((RoomOffer a, RoomOffer b) =>
          a.total.minorUnits.compareTo(b.total.minorUnits));
    }
    return grouped;
  }
}
