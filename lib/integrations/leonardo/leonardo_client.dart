import '../../core/network/api_client.dart';
import '../../core/result.dart';
import '../../domain/media.dart';

/// Client for **Leonardo** (Leonardo Worldwide) - the hospitality media
/// platform that hotels use to manage and syndicate their photography.
///
/// In the LuxeStays architecture Leonardo is the *system of record for
/// pictures*, in the same way SynXis is for inventory and the CMS is for words.
/// A property's marketing team uploads and re-crops there; the app consumes
/// whatever the current approved set is, so a hotel can refresh its imagery
/// without an app release and without a CMS edit.
///
/// ### Contract note
/// Leonardo's media APIs and content feeds are provisioned per chain under a
/// partner agreement rather than published openly, so the shapes below are
/// modelled on their content-feed/media-library concepts (asset id, category,
/// caption, rendition URLs) and are matched exactly by `tool/mock_server`.
/// Everything vendor-specific is confined to this file plus
/// [LeonardoUrlBuilder] - see `docs/05-INTEGRATION-LEONARDO.md`.
class LeonardoClient {
  LeonardoClient({required this._client});

  final ApiClient _client;

  /// All approved media for a property.
  Future<Result<List<LeonardoAssetDto>>> propertyMedia(
    String hotelId, {
    String? category,
    int limit = 60,
  }) {
    return _client.getJson<List<LeonardoAssetDto>>(
      '/v1/properties/$hotelId/media',
      query: <String, Object?>{
        'limit': limit,
        'category': ?category,
        // Ask Leonardo for the approved, rights-cleared set only. Shipping an
        // expired-licence image in a booking flow is a legal problem, not a
        // cosmetic one.
        'status': 'approved',
      },
      decode: (Object? json) {
        final Map<String, Object?> root = JsonRead.object(json, 'root');
        return JsonRead.objectList(
          root['assets'],
          'assets',
        ).map(LeonardoAssetDto.fromJson).toList(growable: false);
      },
    );
  }

  /// Media filed against a specific room type code.
  Future<Result<List<LeonardoAssetDto>>> roomTypeMedia({
    required String hotelId,
    required String roomTypeCode,
  }) {
    return _client.getJson<List<LeonardoAssetDto>>(
      '/v1/properties/$hotelId/media',
      query: <String, Object?>{
        'roomTypeCode': roomTypeCode,
        'status': 'approved',
      },
      decode: (Object? json) {
        final Map<String, Object?> root = JsonRead.object(json, 'root');
        return JsonRead.objectList(
          root['assets'],
          'assets',
        ).map(LeonardoAssetDto.fromJson).toList(growable: false);
      },
    );
  }
}

class LeonardoAssetDto {
  const LeonardoAssetDto({
    required this.mediaId,
    required this.deliveryUrl,
    required this.category,
    this.caption = '',
    this.credit,
    this.width,
    this.height,
    this.isPrimary = false,
    this.roomTypeCodes = const <String>[],
    this.tags = const <String>[],
    this.licenceExpiresAt,
  });

  factory LeonardoAssetDto.fromJson(Map<String, Object?> json) {
    return LeonardoAssetDto(
      mediaId: JsonRead.string(json, 'mediaId'),
      deliveryUrl: JsonRead.string(json, 'deliveryUrl'),
      category: JsonRead.stringOrNull(json, 'category') ?? '',
      caption: JsonRead.stringOrNull(json, 'caption') ?? '',
      credit: JsonRead.stringOrNull(json, 'credit'),
      width: json['width'] == null
          ? null
          : JsonRead.intOf(json, 'width', fallback: 0),
      height: json['height'] == null
          ? null
          : JsonRead.intOf(json, 'height', fallback: 0),
      isPrimary: JsonRead.boolOf(json, 'isPrimary'),
      roomTypeCodes:
          (json['roomTypeCodes'] as List<Object?>? ?? const <Object?>[])
              .map((Object? e) => e.toString())
              .toList(growable: false),
      tags: (json['tags'] as List<Object?>? ?? const <Object?>[])
          .map((Object? e) => e.toString())
          .toList(growable: false),
      licenceExpiresAt: JsonRead.dateOrNull(json, 'licenceExpiresAt'),
    );
  }

  final String mediaId;
  final String deliveryUrl;
  final String category;
  final String caption;
  final String? credit;
  final int? width;
  final int? height;
  final bool isPrimary;
  final List<String> roomTypeCodes;
  final List<String> tags;

  /// Images are licensed, and licences lapse. Filtering client-side as well as
  /// server-side is cheap insurance.
  final DateTime? licenceExpiresAt;

  bool get isLicenceValid =>
      licenceExpiresAt == null || licenceExpiresAt!.isAfter(DateTime.now());

  MediaAsset toDomain() => MediaAsset(
    id: mediaId,
    baseUrl: deliveryUrl,
    category: MediaCategory.fromLeonardo(category),
    altText: caption,
    credit: credit,
    width: width,
    height: height,
    tags: <String>[...tags, ...roomTypeCodes],
    isHero: isPrimary,
  );
}

/// Turns a canonical Leonardo delivery URL into a resized/re-encoded rendition.
///
/// Leonardo (like most hospitality DAMs) exposes renditions as query
/// parameters on the delivery host. Centralising the syntax here means the day
/// the CDN changes `w=` to `width=`, exactly one file changes - and the
/// [MediaTransform] presets used by every widget keep working.
class LeonardoUrlBuilder {
  const LeonardoUrlBuilder({this.enabled = true});

  final bool enabled;

  String build(MediaAsset asset, MediaTransform transform) {
    if (!enabled) {
      return asset.baseUrl;
    }
    final Uri base = Uri.parse(asset.baseUrl);
    return base
        .replace(
          queryParameters: <String, String>{
            ...base.queryParameters,
            if (transform.width != null) 'w': transform.width!.toString(),
            if (transform.height != null) 'h': transform.height!.toString(),
            'q': transform.quality.toString(),
            'fmt': transform.format.name,
            'fit': transform.fit.name,
          },
        )
        .toString();
  }
}
