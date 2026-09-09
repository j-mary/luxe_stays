import 'package:flutter/material.dart';

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
/// The photograph is the only saturated thing on the card. Everything else is
/// type on a neutral surface with a hairline border, so a list of twenty reads
/// as a catalogue rather than as twenty competing tiles.
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Stack(
                  children: <Widget>[
                    AspectRatio(
                      aspectRatio: 3 / 2,
                      child: MediaImage(
                        asset: hero,
                        transform: MediaTransform.card,
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    if (hasMemberRate)
                      const Positioned(
                        top: 12,
                        left: 12,
                        child: _MemberMark(),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              result.hotel.name,
                              style: theme.textTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: _Stars(count: result.hotel.starRating),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        result.hotel.locationLabel.toUpperCase(),
                        style: theme.textTheme.labelSmall,
                      ),
                      if (result.hotel.editorial != null) ...<Widget>[
                        const SizedBox(height: 10),
                        Text(
                          result.hotel.editorial!.headline,
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 14),
                      Divider(height: 1, color: colors.outlineVariant),
                      const SizedBox(height: 14),
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
              ],
            ),
          ),
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
              const SizedBox(height: 3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    offer.averageNightly.format(),
                    style: theme.textTheme.titleLarge?.copyWith(fontSize: 21),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'per night',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${offer.total.format()} total · $nights '
                'night${nights == 1 ? '' : 's'}'
                '${offer.isLastRooms ? ' · ${offer.roomsRemaining} left' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5),
              ),
              if (savings != null) ...<Widget>[
                const SizedBox(height: 4),
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
              minimumSize: const Size(76, 42),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('Add'),
          ),
        ],
      ],
    );
  }
}

/// Membership is marked, not shouted: a light plate over the photograph rather
/// than a saturated pill, so it reads as a detail of the property rather than
/// as an advertisement laid on top of it.
class _MemberMark extends StatelessWidget {
  const _MemberMark();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF2FFFFFF),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.workspace_premium_outlined,
              size: 12,
              color: Color(0xFF9A7B4F),
            ),
            SizedBox(width: 5),
            Text(
              'MEMBER RATE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Color(0xFF14201B),
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
          padding: const EdgeInsets.only(left: 1),
          child: Icon(
            Icons.star_rounded,
            size: 12,
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
      ),
    );
  }
}
