import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'fixtures.dart';
import 'support.dart';

/// Mock headless CMS, shaped like the **Contentful Content Delivery API**.
///
/// It deliberately returns *unresolved links* plus an `includes` block, exactly
/// as Contentful does. That is what makes the client's
/// `ContentfulResponse.resolveLinks` worth having - and what a naive mock that
/// inlines everything would fail to exercise.
Router cmsRouter() {
  final Router router = Router();

  Map<String, Object?> assetLink(String id) => <String, Object?>{
        'sys': <String, Object?>{
          'type': 'Link',
          'linkType': 'Asset',
          'id': id,
        },
      };

  Map<String, Object?> assetRecord(String id, String url, String title) =>
      <String, Object?>{
        'sys': <String, Object?>{'type': 'Asset', 'id': id},
        'fields': <String, Object?>{
          'title': title,
          'file': <String, Object?>{
            // Contentful serves protocol-relative URLs; the client must
            // normalise them.
            'url': url.replaceFirst('http:', ''),
            'contentType': 'image/png',
          },
        },
      };

  router.get('/spaces/<space>/environments/<env>/entries',
      (Request request, String space, String env) {
    final String origin = originOf(request);
    final Map<String, String> q = request.url.queryParameters;
    final String contentType = q['content_type'] ?? '';
    final List<Map<String, Object?>> items = <Map<String, Object?>>[];
    final List<Map<String, Object?>> assets = <Map<String, Object?>>[];

    switch (contentType) {
      case 'hotelContent':
        final String idsParam = q['fields.hotelId[in]'] ?? '';
        final Set<String> wanted = idsParam.isEmpty
            ? mockHotels.map((MockHotel h) => h.id).toSet()
            : idsParam.split(',').map((String s) => s.trim()).toSet();
        for (final MockHotel hotel in mockHotels) {
          if (!wanted.contains(hotel.id)) {
            continue;
          }
          // One property intentionally has no CMS entry, so the "content is
          // never load-bearing" path is exercised on every search.
          if (hotel.id == 'H-CPT-002') {
            continue;
          }
          final String assetId = 'asset-${hotel.id}';
          assets.add(
            assetRecord(
              assetId,
              '$origin/leonardo/img/${hotel.id}-hero.png',
              '${hotel.name} hero',
            ),
          );
          items.add(<String, Object?>{
            'sys': <String, Object?>{
              'type': 'Entry',
              'id': 'entry-${hotel.id}',
              'contentType': <String, Object?>{
                'sys': <String, Object?>{'id': 'hotelContent'},
              },
              'updatedAt': DateTime.now()
                  .subtract(const Duration(days: 6))
                  .toIso8601String(),
            },
            'fields': <String, Object?>{
              'hotelId': hotel.id,
              'headline': hotel.headline,
              'body': hotel.body,
              'signatureExperience': hotel.signature,
              'neighbourhood': hotel.city,
              'amenities': hotel.amenities,
              'highlights': hotel.highlights,
              'tags': hotel.tags,
              'heroImage': assetLink(assetId),
              'updatedAt': DateTime.now()
                  .subtract(const Duration(days: 6))
                  .toIso8601String(),
              'locale': q['locale'] ?? 'en-US',
            },
          });
        }
        break;

      case 'offer':
        for (final MockOffer offer in mockOffers) {
          final String assetId = 'asset-${offer.id}';
          assets.add(
            assetRecord(
              assetId,
              '$origin/leonardo/img/${offer.id}.png',
              offer.title,
            ),
          );
          items.add(<String, Object?>{
            'sys': <String, Object?>{
              'type': 'Entry',
              'id': offer.id,
              'contentType': <String, Object?>{
                'sys': <String, Object?>{'id': 'offer'},
              },
            },
            'fields': <String, Object?>{
              'title': offer.title,
              'subtitle': offer.subtitle,
              'promotionCode': offer.promotionCode,
              'memberOnly': offer.memberOnly,
              'hotelIds': offer.hotelIds,
              'image': assetLink(assetId),
              'termsUrl':
                  '$origin/cms/pages/offer-terms?code=${offer.promotionCode}',
              'startsAt': DateTime.now()
                  .subtract(const Duration(days: 30))
                  .toIso8601String(),
              'endsAt': DateTime.now()
                  .add(const Duration(days: 90))
                  .toIso8601String(),
            },
          });
        }
        break;

      case 'page':
        final String slug = q['fields.slug'] ?? '';
        items.add(<String, Object?>{
          'sys': <String, Object?>{
            'type': 'Entry',
            'id': 'page-$slug',
            'contentType': <String, Object?>{
              'sys': <String, Object?>{'id': 'page'},
            },
          },
          'fields': <String, Object?>{
            'slug': slug,
            'title': _titleForSlug(slug),
            'url': '$origin/cms/pages/$slug',
            'updatedAt': DateTime.now().toIso8601String(),
          },
        });
    }

    return jsonResponse(<String, Object?>{
      'sys': <String, Object?>{'type': 'Array'},
      'total': items.length,
      'skip': 0,
      'limit': int.tryParse(q['limit'] ?? '') ?? 100,
      'items': items,
      if (assets.isNotEmpty) 'includes': <String, Object?>{'Asset': assets},
    });
  });

  /// CMS-rendered pages, loaded by the app inside a WebView.
  router.get('/pages/<slug>', (Request request, String slug) {
    final String reference = request.url.queryParameters['ref'] ?? '';
    return html(_pageHtml(slug, reference));
  });

  return router;
}

String _titleForSlug(String slug) => switch (slug) {
      'rewards-terms' => 'LuxeStays Rewards terms',
      'offer-terms' => 'Offer terms',
      'itinerary' => 'Your itinerary',
      _ => 'LuxeStays',
    };

String _pageHtml(String slug, String reference) {
  final String title = _titleForSlug(slug);
  return '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<style>
  :root { color-scheme: light dark; }
  body { font: 16px/1.6 -apple-system, "Segoe UI", Roboto, sans-serif;
         margin: 0; padding: 24px 20px 48px; max-width: 720px; }
  h1 { font-size: 24px; margin: 0 0 4px; }
  .meta { color: #777; font-size: 13px; margin-bottom: 24px; }
  h2 { font-size: 17px; margin: 28px 0 6px; }
  a.cta { display: inline-block; margin-top: 20px; padding: 12px 18px;
          background: #14342B; color: #fff; border-radius: 10px;
          text-decoration: none; font-weight: 600; }
</style>
</head>
<body>
  <h1>$title</h1>
  <div class="meta">Authored in the CMS · rendered in a WebView · slug <code>$slug</code></div>

  ${reference.isEmpty ? '' : '<p><strong>Booking reference:</strong> $reference</p>'}

  <p>This page is served by the mock CMS and displayed by
  <code>CmsContentWebViewScreen</code>. Legal and programme copy changes far more
  often than the app ships, so it lives here rather than in the binary.</p>

  <h2>Why this is a WebView</h2>
  <p>Rendering CMS rich text natively means owning a rich-text renderer, an
  image-embed strategy and a per-locale typography pass. For content the app
  only displays - and never reasons about - the web page is both cheaper and
  more faithful to what the author previewed.</p>

  <h2>Talking back to the host</h2>
  <p>The button below sends a <code>navigate</code> message over the JavaScript
  bridge. The Flutter host checks it against an allowlist before acting - the
  page cannot push arbitrary routes.</p>

  <a class="cta" href="#" onclick="goToSearch();return false;">Browse hotels</a>

<script>
  function goToSearch() {
    if (window.LuxeStaysBridge && window.LuxeStaysBridge.post) {
      window.LuxeStaysBridge.post('navigate', { route: '/search' });
    }
  }
  document.addEventListener('DOMContentLoaded', function () {
    if (window.LuxeStaysBridge && window.LuxeStaysBridge.post) {
      window.LuxeStaysBridge.post('log', { level: 'info', message: 'cms page $slug ready' });
    }
  });
</script>
</body>
</html>
''';
}
