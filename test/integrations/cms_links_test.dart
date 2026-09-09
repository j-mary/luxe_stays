import 'package:flutter_test/flutter_test.dart';
import 'package:luxe_stays/integrations/cms/cms_models.dart';

/// A Contentful Content Delivery API response never inlines referenced entries
/// or assets - it ships `Link` placeholders plus an `includes` block. These
/// tests pin the resolver that stitches them back together.
Map<String, Object?> _response() => <String, Object?>{
      'sys': <String, Object?>{'type': 'Array'},
      'total': 1,
      'items': <Object?>[
        <String, Object?>{
          'sys': <String, Object?>{'type': 'Entry', 'id': 'entry-1'},
          'fields': <String, Object?>{
            'hotelId': 'H-PAR-001',
            'headline': 'A courtyard hotel',
            'body': 'Eighteen rooms.',
            'amenities': <Object?>['Spa', 'Bar'],
            'heroImage': <String, Object?>{
              'sys': <String, Object?>{
                'type': 'Link',
                'linkType': 'Asset',
                'id': 'asset-1',
              },
            },
            'relatedOffer': <String, Object?>{
              'sys': <String, Object?>{
                'type': 'Link',
                'linkType': 'Entry',
                'id': 'entry-offer',
              },
            },
            'brokenLink': <String, Object?>{
              'sys': <String, Object?>{
                'type': 'Link',
                'linkType': 'Asset',
                'id': 'never-published',
              },
            },
          },
        },
      ],
      'includes': <String, Object?>{
        'Asset': <Object?>[
          <String, Object?>{
            'sys': <String, Object?>{'type': 'Asset', 'id': 'asset-1'},
            'fields': <String, Object?>{
              'title': 'Hero',
              'file': <String, Object?>{
                'url': '//images.example.com/hero.png',
                'contentType': 'image/png',
              },
            },
          },
        ],
        'Entry': <Object?>[
          <String, Object?>{
            'sys': <String, Object?>{'type': 'Entry', 'id': 'entry-offer'},
            'fields': <String, Object?>{'title': 'Stay longer'},
          },
        ],
      },
    };

void main() {
  group('ContentfulResponse', () {
    test('resolves asset and entry links from includes', () {
      final ContentfulResponse response =
          ContentfulResponse.fromJson(_response());
      final Map<String, Object?> fields =
          response.fieldsOf(response.items.first);

      final Object? hero = fields['heroImage'];
      expect(hero, isA<Map<String, Object?>>());
      final Map<String, Object?> file =
          ((hero! as Map<String, Object?>)['fields']!
              as Map<String, Object?>)['file']! as Map<String, Object?>;
      expect(file['url'], '//images.example.com/hero.png');

      final Map<String, Object?> offer =
          fields['relatedOffer']! as Map<String, Object?>;
      expect(
          (offer['fields']! as Map<String, Object?>)['title'], 'Stay longer');
    });

    test('an unpublished reference resolves to null instead of throwing', () {
      // This is the real-world case: an entry is published, the asset it points
      // at is not. It must degrade, not crash the screen.
      final ContentfulResponse response =
          ContentfulResponse.fromJson(_response());
      final Map<String, Object?> fields =
          response.fieldsOf(response.items.first);
      expect(fields['brokenLink'], isNull);
    });

    test('maps into the domain, normalising protocol-relative asset URLs', () {
      final ContentfulResponse response =
          ContentfulResponse.fromJson(_response());
      final CmsHotelContent content =
          CmsHotelContent.fromFields(response.fieldsOf(response.items.first));

      expect(content.hotelId, 'H-PAR-001');
      expect(content.headline, 'A courtyard hotel');
      expect(content.amenities, <String>['Spa', 'Bar']);
      expect(content.heroImageUrl, 'https://images.example.com/hero.png');
    });

    test('handles a response with no includes at all', () {
      final ContentfulResponse response =
          ContentfulResponse.fromJson(<String, Object?>{
        'items': <Object?>[
          <String, Object?>{
            'sys': <String, Object?>{'id': 'e1'},
            'fields': <String, Object?>{'hotelId': 'H-1', 'headline': 'x'},
          },
        ],
        'total': 1,
      });
      expect(response.isEmpty, isFalse);
      expect(
        CmsHotelContent.fromFields(response.fieldsOf(response.items.first))
            .heroImageUrl,
        isNull,
      );
    });
  });
}
