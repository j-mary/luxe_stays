import '../../core/network/api_client.dart';
import '../../domain/hotel.dart';

/// Headless-CMS payloads, shaped like the **Contentful Content Delivery API**.
///
/// Contentful is used as the reference implementation because its response
/// envelope - `items` + `includes` + `Link` references - is the shape almost
/// every headless CMS converged on (Strapi, Sanity, Storyblok and Kontent all
/// do a version of it). Porting to another CMS means rewriting this file and
/// nothing else.
///
/// The interesting part is [ContentfulResponse.resolveLinks]. A CDA response
/// does not inline referenced entries or assets: it returns
/// `{"sys":{"type":"Link","linkType":"Asset","id":"..."}}` placeholders and
/// ships the real records in `includes`. Forgetting to resolve them is the
/// classic first-week Contentful bug - the app renders empty images and nobody
/// can see why.
class ContentfulResponse {
  const ContentfulResponse({
    required this.items,
    required this.entryIncludes,
    required this.assetIncludes,
    this.total = 0,
  });

  factory ContentfulResponse.fromJson(Object? json) {
    final Map<String, Object?> root = JsonRead.object(json, 'root');
    final Map<String, Object?> includes = root['includes'] == null
        ? const <String, Object?>{}
        : JsonRead.object(root['includes'], 'includes');

    Map<String, Map<String, Object?>> index(Object? list) {
      if (list == null) {
        return <String, Map<String, Object?>>{};
      }
      final Map<String, Map<String, Object?>> out =
          <String, Map<String, Object?>>{};
      for (final Map<String, Object?> item in JsonRead.objectList(
        list,
        'includes',
      )) {
        final Map<String, Object?> sys = JsonRead.object(item['sys'], 'sys');
        out[JsonRead.string(sys, 'id')] = item;
      }
      return out;
    }

    return ContentfulResponse(
      items: JsonRead.objectList(root['items'], 'items'),
      entryIncludes: index(includes['Entry']),
      assetIncludes: index(includes['Asset']),
      total: JsonRead.intOf(root, 'total', fallback: 0),
    );
  }

  final List<Map<String, Object?>> items;
  final Map<String, Map<String, Object?>> entryIncludes;
  final Map<String, Map<String, Object?>> assetIncludes;
  final int total;

  bool get isEmpty => items.isEmpty;

  /// Replaces every `Link` in [value] with the record it points at.
  ///
  /// [depth] counts **link hops, not structural nesting**, and the distinction
  /// is the whole reason this method has a comment.
  ///
  /// Following links has to be bounded, because a CMS graph can be cyclic
  /// (hotel → related offer → hotel) and an unbounded resolver on the main
  /// isolate is a hang. Walking into a plain nested object cannot loop: the
  /// payload came out of `jsonDecode`, so it is a tree. Charging both against
  /// the same budget is therefore all cost and no benefit - and it silently
  /// destroys data, because a resolved asset's own `fields.file.url` sits four
  /// plain levels below the link that reached it. Counting those levels made
  /// the budget run out exactly there, so the asset resolved, the object
  /// looked right, and every image URL in it was null.
  Object? resolveLinks(Object? value, {int depth = 0, int maxDepth = 4}) {
    if (value is List) {
      return value
          .map((Object? e) => resolveLinks(e, depth: depth, maxDepth: maxDepth))
          .toList(growable: false);
    }
    if (value is! Map) {
      return value;
    }

    final Object? sysRaw = value['sys'];
    if (sysRaw is Map && sysRaw['type'] == 'Link') {
      if (depth >= maxDepth) {
        // Link budget spent. Stop following rather than risk a cycle.
        return null;
      }
      final String linkType = (sysRaw['linkType'] as Object?)?.toString() ?? '';
      final String id = (sysRaw['id'] as Object?)?.toString() ?? '';
      final Map<String, Object?>? target = switch (linkType) {
        'Asset' => assetIncludes[id],
        'Entry' => entryIncludes[id],
        _ => null,
      };
      if (target == null) {
        // An unresolved link is usually a publish-state mismatch: the entry is
        // published, the thing it references is not. Returning null (and
        // logging upstream) is better than crashing the screen.
        return null;
      }
      // Only a hop across a link spends budget.
      return resolveLinks(target, depth: depth + 1, maxDepth: maxDepth);
    }

    return value.map(
      (Object? key, Object? child) => MapEntry<String, Object?>(
        key.toString(),
        resolveLinks(child, depth: depth, maxDepth: maxDepth),
      ),
    );
  }

  /// `fields` of an item, with all links resolved.
  Map<String, Object?> fieldsOf(Map<String, Object?> item) {
    final Object? resolved = resolveLinks(item['fields']);
    return resolved is Map<String, Object?>
        ? resolved
        : JsonRead.object(resolved, 'fields');
  }

  String idOf(Map<String, Object?> item) =>
      JsonRead.string(JsonRead.object(item['sys'], 'sys'), 'id');
}

/// CMS-owned copy for a property.
class CmsHotelContent {
  const CmsHotelContent({
    required this.hotelId,
    required this.headline,
    required this.body,
    this.signatureExperience,
    this.neighbourhood,
    this.amenities = const <String>[],
    this.highlights = const <String>[],
    this.tags = const <String>[],
    this.heroImageUrl,
    this.updatedAt,
    this.locale = 'en-US',
  });

  factory CmsHotelContent.fromFields(Map<String, Object?> fields) {
    return CmsHotelContent(
      // The join key back to SynXis. Every hotel entry in the CMS carries the
      // CRS hotel id; content and inventory are matched on it, never on name.
      hotelId: JsonRead.string(fields, 'hotelId'),
      headline: JsonRead.stringOrNull(fields, 'headline') ?? '',
      body: JsonRead.stringOrNull(fields, 'body') ?? '',
      signatureExperience: JsonRead.stringOrNull(fields, 'signatureExperience'),
      neighbourhood: JsonRead.stringOrNull(fields, 'neighbourhood'),
      amenities: _stringList(fields['amenities']),
      highlights: _stringList(fields['highlights']),
      tags: _stringList(fields['tags']),
      heroImageUrl: _assetUrl(fields['heroImage']),
      updatedAt: JsonRead.dateOrNull(fields, 'updatedAt'),
      locale: JsonRead.stringOrNull(fields, 'locale') ?? 'en-US',
    );
  }

  final String hotelId;
  final String headline;
  final String body;
  final String? signatureExperience;
  final String? neighbourhood;
  final List<String> amenities;
  final List<String> highlights;
  final List<String> tags;
  final String? heroImageUrl;
  final DateTime? updatedAt;
  final String locale;

  HotelEditorial toEditorial() => HotelEditorial(
    headline: headline,
    body: body,
    signatureExperience: signatureExperience,
    neighbourhood: neighbourhood,
    updatedAt: updatedAt,
    locale: locale,
  );

  static List<String> _stringList(Object? value) {
    if (value is List) {
      return value.map((Object? e) => e.toString()).toList(growable: false);
    }
    return const <String>[];
  }

  /// A resolved Contentful asset carries `fields.file.url`, protocol-relative.
  static String? _assetUrl(Object? asset) {
    if (asset is! Map) {
      return null;
    }
    final Object? fields = asset['fields'];
    if (fields is! Map) {
      return null;
    }
    final Object? file = fields['file'];
    if (file is! Map) {
      return null;
    }
    final String? url = (file['url'] as Object?)?.toString();
    if (url == null) {
      return null;
    }
    return url.startsWith('//') ? 'https:$url' : url;
  }
}

/// A merchandising offer surfaced on the home screen and in search.
class CmsOffer {
  const CmsOffer({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.promotionCode,
    this.imageUrl,
    this.hotelIds = const <String>[],
    this.termsUrl,
    this.startsAt,
    this.endsAt,
    this.memberOnly = false,
  });

  factory CmsOffer.fromFields(String id, Map<String, Object?> fields) {
    return CmsOffer(
      id: id,
      title: JsonRead.stringOrNull(fields, 'title') ?? '',
      subtitle: JsonRead.stringOrNull(fields, 'subtitle') ?? '',
      // Marketing configures the code in the CMS; the app passes it straight
      // to SynXis as the promotion code. That is the whole integration: no
      // release needed to run a campaign.
      promotionCode: JsonRead.stringOrNull(fields, 'promotionCode') ?? '',
      imageUrl: CmsHotelContent._assetUrl(fields['image']),
      hotelIds: CmsHotelContent._stringList(fields['hotelIds']),
      termsUrl: JsonRead.stringOrNull(fields, 'termsUrl'),
      startsAt: JsonRead.dateOrNull(fields, 'startsAt'),
      endsAt: JsonRead.dateOrNull(fields, 'endsAt'),
      memberOnly: JsonRead.boolOf(fields, 'memberOnly'),
    );
  }

  final String id;
  final String title;
  final String subtitle;
  final String promotionCode;
  final String? imageUrl;
  final List<String> hotelIds;

  /// Terms live as a CMS page and are shown in a WebView - legal copy changes
  /// far more often than app releases ship.
  final String? termsUrl;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool memberOnly;

  bool get isLive {
    final DateTime now = DateTime.now();
    final bool started = startsAt == null || now.isAfter(startsAt!);
    final bool notEnded = endsAt == null || now.isBefore(endsAt!);
    return started && notEnded;
  }
}

/// A CMS-authored page rendered inside a WebView (terms, loyalty rules,
/// destination guides, itinerary pages).
class CmsPage {
  const CmsPage({
    required this.slug,
    required this.title,
    required this.url,
    this.updatedAt,
  });

  factory CmsPage.fromFields(Map<String, Object?> fields) => CmsPage(
    slug: JsonRead.stringOrNull(fields, 'slug') ?? '',
    title: JsonRead.stringOrNull(fields, 'title') ?? '',
    url: JsonRead.stringOrNull(fields, 'url') ?? '',
    updatedAt: JsonRead.dateOrNull(fields, 'updatedAt'),
  );

  final String slug;
  final String title;
  final String url;
  final DateTime? updatedAt;
}
