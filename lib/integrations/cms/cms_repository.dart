import '../../core/logging/app_logger.dart';
import '../../core/result.dart';
import 'cms_client.dart';
import 'cms_models.dart';

/// Domain-facing CMS access.
///
/// The governing rule: **content is never load-bearing.** Every method here
/// degrades to an empty result rather than propagating a failure, because a
/// missing marketing paragraph must not stop a guest from booking a room. The
/// failure is logged (and would be alerted on), but the booking funnel stays
/// open. Compare with `SynxisRepository`, where a failure genuinely must
/// surface: if the CRS is down, there is nothing to sell.
class CmsRepository {
  CmsRepository({
    required this._client,
    required this._logger,
    this.cacheTtl = const Duration(minutes: 15),
  });

  final CmsClient _client;
  final AppLogger _logger;
  final Duration cacheTtl;

  final Map<String, CmsHotelContent> _hotelContentCache =
      <String, CmsHotelContent>{};
  DateTime? _hotelContentFetchedAt;

  List<CmsOffer>? _offersCache;
  DateTime? _offersFetchedAt;

  /// Editorial content keyed by hotel id. Missing entries are simply absent
  /// from the map; callers treat that as "no content yet".
  Future<Map<String, CmsHotelContent>> hotelContent(
    List<String> hotelIds, {
    String locale = 'en-US',
  }) async {
    final List<String> missing = hotelIds
        .where((String id) => !_hotelContentCache.containsKey(id))
        .toList(growable: false);

    final bool cacheFresh =
        _hotelContentFetchedAt != null &&
        DateTime.now().difference(_hotelContentFetchedAt!) < cacheTtl;

    if (missing.isEmpty && cacheFresh) {
      return _subsetOf(hotelIds);
    }

    final Result<List<CmsHotelContent>> result = await _client.hotelContent(
      missing.isEmpty ? hotelIds : missing,
      locale: locale,
    );

    result.fold<void>(
      (List<CmsHotelContent> content) {
        for (final CmsHotelContent entry in content) {
          _hotelContentCache[entry.hotelId] = entry;
        }
        _hotelContentFetchedAt = DateTime.now();
        final int notFound = missing.length - content.length;
        if (notFound > 0) {
          // Worth surfacing: it usually means an entry exists but is not
          // published in this environment, which content editors cannot see.
          _logger.info(
            'cms: $notFound propert(ies) have no published content entry',
          );
        }
      },
      (Object failure) => _logger.warn(
        'cms: hotel content unavailable, rendering CRS data only',
        error: failure,
      ),
    );

    return _subsetOf(hotelIds);
  }

  Map<String, CmsHotelContent> _subsetOf(List<String> hotelIds) {
    final Map<String, CmsHotelContent> out = <String, CmsHotelContent>{};
    for (final String id in hotelIds) {
      final CmsHotelContent? entry = _hotelContentCache[id];
      if (entry != null) {
        out[id] = entry;
      }
    }
    return out;
  }

  Future<List<CmsOffer>> offers({bool memberOnly = false}) async {
    final List<CmsOffer>? cached = _offersCache;
    if (cached != null &&
        _offersFetchedAt != null &&
        DateTime.now().difference(_offersFetchedAt!) < cacheTtl) {
      return cached;
    }

    final Result<List<CmsOffer>> result = await _client.offers(
      memberOnly: memberOnly,
    );

    return result.fold<List<CmsOffer>>(
      (List<CmsOffer> offers) {
        _offersCache = offers;
        _offersFetchedAt = DateTime.now();
        return offers;
      },
      (Object failure) {
        _logger.warn('cms: offers unavailable', error: failure);
        return cached ?? const <CmsOffer>[];
      },
    );
  }

  /// Resolves a slug to the URL the WebView should load.
  Future<String?> pageUrl(String slug) async {
    final Result<CmsPage?> result = await _client.page(slug);
    return result.fold<String?>((CmsPage? page) => page?.url, (Object failure) {
      _logger.warn('cms: page "$slug" unavailable', error: failure);
      return null;
    });
  }

  void clearCache() {
    _hotelContentCache.clear();
    _hotelContentFetchedAt = null;
    _offersCache = null;
    _offersFetchedAt = null;
  }
}
