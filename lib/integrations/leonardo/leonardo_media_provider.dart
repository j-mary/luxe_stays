import '../../core/logging/app_logger.dart';
import '../../core/result.dart';
import '../../domain/media.dart';
import 'leonardo_ai_client.dart';
import 'leonardo_client.dart';
import 'media_provider.dart';

/// The production [MediaProvider]: Leonardo Worldwide for real photography,
/// Leonardo.Ai only for destination mood imagery, and an in-memory cache in
/// front of both.
///
/// The cache is not an optimisation detail - a hotel gallery is requested by
/// the search card, the detail hero, the room list and the cart line, all
/// within a second of each other. Without it, one property view is four
/// identical round trips.
class LeonardoMediaProvider implements MediaProvider {
  LeonardoMediaProvider({
    required this._client,
    required this._logger,
    this._aiClient,
    this._urlBuilder = const LeonardoUrlBuilder(),
    this.cacheTtl = const Duration(minutes: 30),
  });

  final LeonardoClient _client;
  final LeonardoAiClient? _aiClient;
  final AppLogger _logger;
  final LeonardoUrlBuilder _urlBuilder;
  final Duration cacheTtl;

  final Map<String, _CachedGallery> _galleryCache = <String, _CachedGallery>{};

  /// Coalesces concurrent requests for the same property into one call.
  final Map<String, Future<Result<List<MediaAsset>>>> _inFlight =
      <String, Future<Result<List<MediaAsset>>>>{};

  @override
  Future<Result<List<MediaAsset>>> galleryFor(String hotelId) {
    final _CachedGallery? cached = _galleryCache[hotelId];
    if (cached != null && !cached.isStale(cacheTtl)) {
      return Future<Result<List<MediaAsset>>>.value(
        Ok<List<MediaAsset>>(cached.assets),
      );
    }

    final Future<Result<List<MediaAsset>>>? pending = _inFlight[hotelId];
    if (pending != null) {
      return pending;
    }

    final Future<Result<List<MediaAsset>>> request = _fetchGallery(hotelId);
    _inFlight[hotelId] = request;
    return request.whenComplete(() => _inFlight.remove(hotelId));
  }

  Future<Result<List<MediaAsset>>> _fetchGallery(String hotelId) async {
    final Result<List<LeonardoAssetDto>> result = await _client.propertyMedia(
      hotelId,
    );

    return result.map((List<LeonardoAssetDto> dtos) {
      final List<MediaAsset> assets = dtos
          .where((LeonardoAssetDto d) => d.isLicenceValid)
          .map((LeonardoAssetDto d) => d.toDomain())
          .toList();
      final int dropped = dtos.length - assets.length;
      if (dropped > 0) {
        _logger.warn(
          'leonardo: dropped $dropped asset(s) with an expired licence',
          context: <String, Object?>{'hotelId': hotelId},
        );
      }
      // Hero first, then a stable category order, so the gallery does not
      // reshuffle between launches.
      assets.sort((MediaAsset a, MediaAsset b) {
        if (a.isHero != b.isHero) {
          return a.isHero ? -1 : 1;
        }
        return a.category.index.compareTo(b.category.index);
      });
      _galleryCache[hotelId] = _CachedGallery(
        assets: assets,
        at: DateTime.now(),
      );
      return assets;
    });
  }

  @override
  Future<Result<List<MediaAsset>>> roomMedia({
    required String hotelId,
    required String roomTypeCode,
  }) async {
    // Serve from the property gallery when we already have it: room media is a
    // subset, and the tag carries the room-type code.
    final _CachedGallery? cached = _galleryCache[hotelId];
    if (cached != null && !cached.isStale(cacheTtl)) {
      final List<MediaAsset> matches = cached.assets
          .where((MediaAsset a) => a.tags.contains(roomTypeCode))
          .toList(growable: false);
      if (matches.isNotEmpty) {
        return Ok<List<MediaAsset>>(matches);
      }
    }

    final Result<List<LeonardoAssetDto>> result = await _client.roomTypeMedia(
      hotelId: hotelId,
      roomTypeCode: roomTypeCode,
    );
    return result.map(
      (List<LeonardoAssetDto> dtos) => dtos
          .where((LeonardoAssetDto d) => d.isLicenceValid)
          .map((LeonardoAssetDto d) => d.toDomain())
          .toList(growable: false),
    );
  }

  /// Destination mood imagery for editorial surfaces. Falls back silently to an
  /// empty list - inspiration content is never allowed to break a screen.
  Future<List<MediaAsset>> destinationImagery({
    required String destinationId,
    required String prompt,
  }) async {
    final LeonardoAiClient? ai = _aiClient;
    if (ai == null) {
      return const <MediaAsset>[];
    }
    final Result<List<MediaAsset>> result = await ai.generateDestinationImagery(
      prompt: prompt,
      destinationId: destinationId,
    );
    return result.valueOrNull ?? const <MediaAsset>[];
  }

  @override
  String urlFor(MediaAsset asset, MediaTransform transform) {
    // Generated assets are served from the AI vendor's signed URLs, which do
    // not accept our rendition parameters.
    if (asset.source == MediaSource.leonardoAi) {
      return asset.baseUrl;
    }
    return _urlBuilder.build(asset, transform);
  }

  void clearCache() {
    _galleryCache.clear();
  }
}

class _CachedGallery {
  const _CachedGallery({required this.assets, required this.at});

  final List<MediaAsset> assets;
  final DateTime at;

  bool isStale(Duration ttl) => DateTime.now().difference(at) > ttl;
}
