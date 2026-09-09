import 'media.dart';

/// A bookable property.
///
/// Deliberately assembled from **three** sources, which is the whole point of
/// this POC:
///  * identity, location and bookability come from SynXis (the CRS is the
///    system of record for what can actually be sold);
///  * [editorial], [highlights] and [amenities] come from the CMS (marketing
///    owns the words, and can change them without an app release);
///  * [gallery] comes from Leonardo (the hotel's own media library).
///
/// The merge happens in `HotelRepository`, not in the widgets - see
/// `docs/01-ARCHITECTURE.md`.
class Hotel {
  const Hotel({
    required this.id,
    required this.chainId,
    required this.name,
    required this.city,
    required this.country,
    required this.starRating,
    this.latitude,
    this.longitude,
    this.address = '',
    this.editorial,
    this.gallery = const <MediaAsset>[],
    this.amenities = const <String>[],
    this.highlights = const <String>[],
    this.tags = const <String>[],
    this.guestRating,
    this.reviewCount = 0,
  });

  /// SynXis property/hotel id. This is the join key across every system: CMS
  /// entries reference it, Leonardo files media under it, Salesforce
  /// transaction journals record it.
  final String id;
  final String chainId;
  final String name;
  final String city;
  final String country;
  final int starRating;
  final double? latitude;
  final double? longitude;
  final String address;

  /// Long-form marketing copy from the CMS. Null until the CMS call resolves -
  /// the UI renders the SynXis-only version first so search never blocks on
  /// content.
  final HotelEditorial? editorial;
  final List<MediaAsset> gallery;
  final List<String> amenities;
  final List<String> highlights;
  final List<String> tags;
  final double? guestRating;
  final int reviewCount;

  MediaAsset? get heroImage {
    if (gallery.isEmpty) {
      return null;
    }
    for (final MediaAsset asset in gallery) {
      if (asset.isHero) {
        return asset;
      }
    }
    return gallery.first;
  }

  String get locationLabel => '$city, $country';

  Hotel mergeContent({
    HotelEditorial? editorial,
    List<MediaAsset>? gallery,
    List<String>? amenities,
    List<String>? highlights,
    List<String>? tags,
  }) {
    return Hotel(
      id: id,
      chainId: chainId,
      name: name,
      city: city,
      country: country,
      starRating: starRating,
      latitude: latitude,
      longitude: longitude,
      address: address,
      editorial: editorial ?? this.editorial,
      gallery: gallery ?? this.gallery,
      amenities: amenities ?? this.amenities,
      highlights: highlights ?? this.highlights,
      tags: tags ?? this.tags,
      guestRating: guestRating,
      reviewCount: reviewCount,
    );
  }

  @override
  bool operator ==(Object other) => other is Hotel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// CMS-owned copy for a property.
class HotelEditorial {
  const HotelEditorial({
    required this.headline,
    required this.body,
    this.signatureExperience,
    this.neighbourhood,
    this.updatedAt,
    this.locale = 'en-US',
  });

  final String headline;
  final String body;
  final String? signatureExperience;
  final String? neighbourhood;
  final DateTime? updatedAt;
  final String locale;
}
