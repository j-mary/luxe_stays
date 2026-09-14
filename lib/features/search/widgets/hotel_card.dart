import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/utils/money.dart';
import '../../../data/hotel_repository.dart';
import '../../../domain/media.dart';
import '../../../domain/rate.dart';
import '../../../shared/widgets/media_image.dart';

/// One search result.
///
/// Shows, in one glance, the three things a guest decides on: the picture
/// (Leonardo), the promise (the CMS headline) and the price (the CRS). Any one
/// of the three can be missing and the card still renders — which is the
/// visible consequence of the rule that content is never load-bearing.
///
/// Laid out as a page in a catalogue rather than as a tile in a grid: the
/// photograph runs the full width with no corner radius, the type sits on the
/// paper beneath it, and a hairline rule separates one property from the next.
/// A bordered rounded card would put a frame around every result and turn a
/// list of twenty into twenty competing objects; a rule turns it into a
/// sequence.
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
    final ColorScheme colors = theme.colorScheme;
    final RoomOffer? leadIn = result.leadInOffer;
    final bool hasMemberRate = result.bestMemberOffer != null;
    final MediaAsset? hero = result.hotel.heroImage;

    return Material(
      color: colors.surface,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Stack(
              children: <Widget>[
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: MediaImage(
                    asset: hero,
                    transform: MediaTransform.card,
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                if (hasMemberRate)
                  const Positioned(top: 0, left: 0, child: _MemberMark()),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          result.hotel.locationLabel.toUpperCase(),
                          style: theme.textTheme.labelSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _Stars(count: result.hotel.starRating),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    result.hotel.name,
                    style: theme.textTheme.titleLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (result.hotel.editorial != null) ...<Widget>[
                    const SizedBox(height: 9),
                    Text(
                      result.hotel.editorial!.headline,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (leadIn == null)
                    Text(
                      'No availability for these dates',
                      style: theme.textTheme.bodySmall,
                    )
                  else
                    _PriceRow(
                      offer: leadIn,
                      onQuickAdd: onQuickAdd == null
                          ? null
                          : () => onQuickAdd!(leadIn),
                    ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: colors.outlineVariant),
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
    final ColorScheme colors = theme.colorScheme;
    final Money? savings = offer.savings;
    final int nights = offer.stay.nights;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('FROM', style: theme.textTheme.labelSmall),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  // The price is the one number set in the display serif: it is
                  // what the guest came for, and it is the only place on the
                  // card where a figure earns that much weight.
                  Text(
                    offer.averageNightly.format(),
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'per night',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '${offer.total.format()} total · $nights '
                'night${nights == 1 ? '' : 's'}'
                '${offer.isLastRooms ? ' · ${offer.roomsRemaining} left' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5),
              ),
              if (savings != null) ...<Widget>[
                const SizedBox(height: 5),
                Text(
                  'Saves ${savings.format()} on the public rate',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (onQuickAdd != null) ...<Widget>[
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: onQuickAdd,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(84, 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('Add'),
          ),
        ],
      ],
    );
  }
}

/// Membership is marked, not shouted: a small ink plate set flush into the
/// corner of the photograph, gold type on near-black. Flush rather than inset
/// because a floating pill reads as a sticker laid over the picture, while a
/// corner that meets both edges reads as part of the plate the picture is
/// printed on.
class _MemberMark extends StatelessWidget {
  const _MemberMark();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: AppTheme.plate.withAlpha(242)),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(12, 7, 13, 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.workspace_premium_outlined,
              size: 12,
              color: AppTheme.plateGold,
            ),
            SizedBox(width: 6),
            Text(
              'MEMBER RATE',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: AppTheme.plateGold,
              ),
            ),
          ],
        ),
      ),
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
        (int _) => Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Icon(
            Icons.star_rounded,
            size: 11,
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
      ),
    );
  }
}
