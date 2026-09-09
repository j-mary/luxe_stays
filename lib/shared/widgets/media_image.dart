import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/media.dart';
import '../../integrations/leonardo/media_provider.dart';

/// Renders a Leonardo-managed image at exactly the size it will be drawn at.
///
/// Three things happen here that matter for a media-heavy travel app on a
/// mid-range Android handset with a metered connection:
///
///  1. **Right-sized requests.** The rendition is scaled by the device pixel
///     ratio, so a 120pt thumbnail on a 3x screen fetches 360px - not the 4000px
///     master the hotel uploaded.
///  2. **Decode caching.** `memCacheWidth` caps the decoded bitmap, which is
///     what actually blows up the image cache; a 4000px JPEG decodes to ~64 MB
///     of RAM regardless of how small you draw it.
///  3. **Provenance.** AI-generated imagery renders a visible badge. A guest
///     must never mistake a generated impression for a photograph of the room
///     they are booking.
class MediaImage extends ConsumerWidget {
  const MediaImage({
    required this.asset,
    required this.transform,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.height,
    this.width,
    this.showProvenanceBadge = true,
    super.key,
  });

  final MediaAsset? asset;
  final MediaTransform transform;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final double? height;
  final double? width;
  final bool showProvenanceBadge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MediaAsset? media = asset;
    final BorderRadius radius = borderRadius ?? BorderRadius.circular(12);

    if (media == null) {
      return ClipRRect(
        borderRadius: radius,
        child: _Placeholder(height: height, width: width),
      );
    }

    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final MediaTransform scaled = transform.forDevicePixelRatio(dpr);
    final MediaProvider provider = ref.watch(mediaProviderProvider);
    final String url = provider.urlFor(media, scaled);

    final Widget image = CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      height: height,
      width: width,
      memCacheWidth: scaled.width,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (BuildContext context, String _) =>
          _Placeholder(height: height, width: width),
      errorWidget: (BuildContext context, String _, Object __) =>
          _Placeholder(height: height, width: width, failed: true),
    );

    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          Semantics(
            image: true,
            label: media.altText.isEmpty ? 'Hotel photograph' : media.altText,
            child: image,
          ),
          if (showProvenanceBadge && media.source == MediaSource.leonardoAi)
            const Positioned(
              left: 8,
              bottom: 8,
              child: _ProvenanceBadge(label: 'AI impression'),
            ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.height, this.width, this.failed = false});

  final double? height;
  final double? width;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      height: height,
      width: width,
      color: colors.surfaceContainerHighest,
      alignment: Alignment.center,
      child: failed
          ? Icon(Icons.image_not_supported_outlined,
              color: colors.onSurfaceVariant)
          : null,
    );
  }
}

class _ProvenanceBadge extends StatelessWidget {
  const _ProvenanceBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
