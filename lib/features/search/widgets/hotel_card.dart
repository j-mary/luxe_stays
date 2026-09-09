import 'package:flutter/material.dart';

import '../../../core/utils/money.dart';
import '../../../data/hotel_repository.dart';
import '../../../domain/media.dart';
import '../../../domain/rate.dart';
import '../../../shared/widgets/media_image.dart';

/// One search result.
///
/// Shows, in one glance, the three things a luxury guest decides on: the
/// picture (Leonardo), the promise (CMS editorial headline) and the price
/// (SynXis). If any one of the three is missing the card still renders - which
/// is the visible consequence of the "content is never load-bearing" rule.
class HotelCard extends StatelessWidget {
  const HotelCard({
    required this.result,
    required this.onTap,
    this.onQuickAdd,
    super.key,
  });

  final HotelSearchResult result;
  final VoidCallback onTap;
  final void Function(RoomOffer offer)? onQuickAdd;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final RoomOffer? leadIn = result.leadInOffer;
    final RoomOffer? memberOffer = result.bestMemberOffer;
    final MediaAsset? hero = result.hotel.heroImage;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Stack(
              children: <Widget>[
                AspectRatio(
                  aspectRatio: 16 / 10,
                  child: MediaImage(
                    asset: hero,
                    transform: MediaTransform.card,
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                if (memberOffer != null)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: _Badge(
                      label: 'Member rate',
                      color: theme.colorScheme.primary,
                    ),
                  ),
                if (leadIn != null && leadIn.isLastRooms)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: _Badge(
                      label: '${leadIn.roomsRemaining} left',
                      color: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          result.hotel.name,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Stars(count: result.hotel.starRating),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    result.hotel.locationLabel,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (result.hotel.editorial != null) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      result.hotel.editorial!.headline,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontStyle: FontStyle.italic),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (leadIn == null)
                    Text(
                      'No availability for these dates',
                      style: theme.textTheme.bodySmall,
                    )
                  else
                    _PriceRow(
                      offer: leadIn,
                      onQuickAdd:
                          onQuickAdd == null ? null : () => onQuickAdd!(leadIn),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.offer, this.onQuickAdd});

  final RoomOffer offer;
  final VoidCallback? onQuickAdd;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Money? savings = offer.savings;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'From',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    offer.averageNightly.format(),
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 4),
                  Text('/ night', style: theme.textTheme.bodySmall),
                ],
              ),
              Text(
                '${offer.total.format()} total · ${offer.stay.nights} night'
                '${offer.stay.nights == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (savings != null)
                Text(
                  'You save ${savings.format()}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        if (onQuickAdd != null)
          FilledButton.tonal(
            onPressed: onQuickAdd,
            child: const Text('Add'),
          ),
      ],
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(
        count.clamp(0, 5).toInt(),
        (int _) => Icon(
          Icons.star_rounded,
          size: 14,
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
