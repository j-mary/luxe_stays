/// A single image (or video poster) delivered by Leonardo.
///
/// The app never hard-codes a CDN path. It holds a [MediaAsset] and asks the
/// active media provider for a URL at the exact pixel size the widget needs -
/// which is how a 400-hotel gallery stays under a sane data budget on cellular.
class MediaAsset {
  const MediaAsset({
    required this.id,
    required this.baseUrl,
    required this.category,
    this.altText = '',
    this.credit,
    this.width,
    this.height,
    this.tags = const <String>[],
    this.isHero = false,
    this.source = MediaSource.leonardo,
  });

  /// Leonardo media id (their `mediaId` / asset guid).
  final String id;

  /// Canonical, un-transformed delivery URL.
  final String baseUrl;
  final MediaCategory category;
  final String altText;
  final String? credit;
  final int? width;
  final int? height;
  final List<String> tags;
  final bool isHero;
  final MediaSource source;

  double? get aspectRatio => (width != null && height != null && height! > 0)
      ? width! / height!
      : null;
}

enum MediaCategory {
  exterior,
  lobby,
  guestRoom,
  suite,
  dining,
  spa,
  pool,
  meeting,
  destination,
  unknown;

  /// Leonardo's `category` vocabulary is free-ish text that varies by chain,
  /// so we normalise aggressively rather than trusting an exact match.
  static MediaCategory fromLeonardo(String? raw) {
    final String key =
        (raw ?? '').toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '');
    switch (key) {
      case 'exterior':
      case 'hotelexterior':
        return MediaCategory.exterior;
      case 'lobby':
      case 'publicspace':
        return MediaCategory.lobby;
      case 'guestroom':
      case 'room':
        return MediaCategory.guestRoom;
      case 'suite':
        return MediaCategory.suite;
      case 'restaurant':
      case 'dining':
      case 'foodandbeverage':
        return MediaCategory.dining;
      case 'spa':
      case 'wellness':
        return MediaCategory.spa;
      case 'pool':
        return MediaCategory.pool;
      case 'meeting':
      case 'eventspace':
        return MediaCategory.meeting;
      case 'destination':
      case 'area':
        return MediaCategory.destination;
      default:
        return MediaCategory.unknown;
    }
  }

  String get label => switch (this) {
        MediaCategory.exterior => 'Exterior',
        MediaCategory.lobby => 'Lobby',
        MediaCategory.guestRoom => 'Rooms',
        MediaCategory.suite => 'Suites',
        MediaCategory.dining => 'Dining',
        MediaCategory.spa => 'Spa',
        MediaCategory.pool => 'Pool',
        MediaCategory.meeting => 'Meetings',
        MediaCategory.destination => 'Destination',
        MediaCategory.unknown => 'Gallery',
      };
}

/// Where the pixels came from. Generative assets are labelled in the UI - a
/// travel brand must never imply an AI render is a photo of the real room.
enum MediaSource { leonardo, leonardoAi, cms }

/// Requested rendition. The provider maps this onto whatever transformation
/// syntax the CDN understands.
class MediaTransform {
  const MediaTransform({
    this.width,
    this.height,
    this.quality = 80,
    this.format = MediaFormat.webp,
    this.fit = MediaFit.cover,
  });

  static const MediaTransform thumbnail =
      MediaTransform(width: 320, height: 214, quality: 70);
  static const MediaTransform card =
      MediaTransform(width: 720, height: 480, quality: 78);
  static const MediaTransform hero =
      MediaTransform(width: 1440, height: 900, quality: 82);

  final int? width;
  final int? height;
  final int quality;
  final MediaFormat format;
  final MediaFit fit;

  /// Scales the request to the device's pixel ratio, capped so we never ask a
  /// 3x phone for a 4320px-wide JPEG.
  MediaTransform forDevicePixelRatio(double ratio, {int maxWidth = 2048}) {
    final int? w = width == null
        ? null
        : (width! * ratio).round().clamp(1, maxWidth).toInt();
    final int? h = height == null
        ? null
        : (height! * ratio).round().clamp(1, maxWidth).toInt();
    return MediaTransform(
      width: w,
      height: h,
      quality: quality,
      format: format,
      fit: fit,
    );
  }
}

enum MediaFormat { webp, jpeg, avif }

enum MediaFit { cover, contain, crop }
