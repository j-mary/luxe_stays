import '../../core/network/api_client.dart';
import '../../core/result.dart';
import 'cms_models.dart';

/// Transport for the headless CMS (Contentful Content Delivery API shape).
///
/// Everything here is a **read** against the CDN-backed delivery endpoint, with
/// a delivery token that is scoped read-only to one space/environment. That is
/// why this client has no `AuthInterceptor`: there is no refresh, no user
/// identity, and the token is safe to ship in the binary (it grants nothing but
/// published, public content). The *management* token, which can write, never
/// leaves the server.
///
/// Docs: https://www.contentful.com/developers/docs/references/content-delivery-api/
class CmsClient {
  CmsClient({
    required this._client,
    required this._spaceId,
    required this._environment,
  });

  final ApiClient _client;
  final String _spaceId;
  final String _environment;

  String get _entries => '/spaces/$_spaceId/environments/$_environment/entries';

  /// Content types, as configured in the CMS.
  static const String typeHotel = 'hotelContent';
  static const String typeOffer = 'offer';
  static const String typePage = 'page';

  /// Editorial content for a batch of properties.
  ///
  /// Batched with `fields.hotelId[in]` rather than one call per hotel: a search
  /// result page holds 20 properties, and 20 sequential CMS round trips is the
  /// difference between a list that renders in 300 ms and one that trickles in
  /// over four seconds.
  Future<Result<List<CmsHotelContent>>> hotelContent(
    List<String> hotelIds, {
    String locale = 'en-US',
  }) {
    return _client.getJson<List<CmsHotelContent>>(
      _entries,
      query: <String, Object?>{
        'content_type': typeHotel,
        'fields.hotelId[in]': hotelIds.join(','),
        'locale': locale,
        // Depth 2 pulls the hero asset and any nested references in one hop.
        'include': 2,
        'limit': hotelIds.length.clamp(1, 100),
      },
      decode: (Object? json) {
        final ContentfulResponse response = ContentfulResponse.fromJson(json);
        return response.items
            .map(
              (Map<String, Object?> item) =>
                  CmsHotelContent.fromFields(response.fieldsOf(item)),
            )
            .toList(growable: false);
      },
    );
  }

  /// Live merchandising offers for the home screen.
  Future<Result<List<CmsOffer>>> offers({
    String locale = 'en-US',
    bool memberOnly = false,
  }) {
    return _client.getJson<List<CmsOffer>>(
      _entries,
      query: <String, Object?>{
        'content_type': typeOffer,
        'locale': locale,
        'include': 2,
        'order': '-sys.updatedAt',
        if (memberOnly) 'fields.memberOnly': true,
        'limit': 20,
      },
      decode: (Object? json) {
        final ContentfulResponse response = ContentfulResponse.fromJson(json);
        return response.items
            .map(
              (Map<String, Object?> item) => CmsOffer.fromFields(
                response.idOf(item),
                response.fieldsOf(item),
              ),
            )
            .where((CmsOffer offer) => offer.isLive)
            .toList(growable: false);
      },
    );
  }

  /// A single CMS page by slug - resolved to a URL the WebView loads.
  Future<Result<CmsPage?>> page(String slug, {String locale = 'en-US'}) {
    return _client.getJson<CmsPage?>(
      _entries,
      query: <String, Object?>{
        'content_type': typePage,
        'fields.slug': slug,
        'locale': locale,
        'limit': 1,
      },
      decode: (Object? json) {
        final ContentfulResponse response = ContentfulResponse.fromJson(json);
        if (response.isEmpty) {
          return null;
        }
        return CmsPage.fromFields(response.fieldsOf(response.items.first));
      },
    );
  }
}
