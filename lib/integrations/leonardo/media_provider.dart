import '../../core/result.dart';
import '../../domain/media.dart';

/// The app's only view of "where pictures come from".
///
/// Widgets depend on this interface, never on a Leonardo client. That is what
/// makes it possible to run the whole UI against a fixture provider in widget
/// tests (no network, deterministic golden images) and to swap the media
/// platform without touching a single screen.
abstract interface class MediaProvider {
  /// The full gallery for a property.
  Future<Result<List<MediaAsset>>> galleryFor(String hotelId);

  /// Media for one room type, matched on the ids the CRS carries.
  Future<Result<List<MediaAsset>>> roomMedia({
    required String hotelId,
    required String roomTypeCode,
  });

  /// Builds a delivery URL at the requested rendition.
  ///
  /// Synchronous and pure: it is called from `build()` on every image, so it
  /// must never touch the network.
  String urlFor(MediaAsset asset, MediaTransform transform);
}

/// A provider that serves a fixed set of assets. Used by widget tests and by
/// the offline/preview mode.
class StaticMediaProvider implements MediaProvider {
  const StaticMediaProvider(this._assets);

  final Map<String, List<MediaAsset>> _assets;

  @override
  Future<Result<List<MediaAsset>>> galleryFor(String hotelId) async =>
      Ok<List<MediaAsset>>(_assets[hotelId] ?? const <MediaAsset>[]);

  @override
  Future<Result<List<MediaAsset>>> roomMedia({
    required String hotelId,
    required String roomTypeCode,
  }) async {
    final List<MediaAsset> all = _assets[hotelId] ?? const <MediaAsset>[];
    return Ok<List<MediaAsset>>(
      all
          .where((MediaAsset a) => a.tags.contains(roomTypeCode))
          .toList(growable: false),
    );
  }

  @override
  String urlFor(MediaAsset asset, MediaTransform transform) => asset.baseUrl;
}
