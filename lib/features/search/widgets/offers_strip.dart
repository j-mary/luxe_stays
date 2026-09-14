import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../integrations/cms/cms_models.dart';
import '../../../shared/widgets/app_snack_bar.dart';
import '../../../shared/widgets/section_heading.dart';
import '../../home/offers_provider.dart';
import '../search_controller.dart';

/// CMS-authored offers. Tapping one applies its promotion code to the search.
///
/// The card has a fixed height because a horizontal list needs a bounded cross
/// axis, so the content is budgeted rather than left to overflow: a single-line
/// serif title, a two-line summary, and a footer pinned to the bottom. Earlier
/// this laid out an unbounded column inside too little height, which clipped
/// the summary mid-line — visually indistinguishable from a rendering bug.
class OffersStrip extends ConsumerWidget {
  const OffersStrip({super.key});

  static const double _cardHeight = 176;
  static const double _cardWidth = 280;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<CmsOffer>> offers = ref.watch(offersProvider);

    return offers.maybeWhen<Widget>(
      orElse: () => const SizedBox.shrink(),
      data: (List<CmsOffer> list) {
        if (list.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionHeading(label: 'OFFERS'),
            SizedBox(
              height: _cardHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (BuildContext context, int index) => _OfferCard(
                  offer: list[index],
                  width: _cardWidth,
                  onApply: () {
                    final HotelSearchController controller = ref.read(
                      searchProvider.notifier,
                    );
                    controller.applyPromotionCode(list[index].promotionCode);
                    controller.search(forceRefresh: true);
                    showAppSnackBar(
                      context,
                      'Offer ${list[index].promotionCode} applied',
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.width,
    required this.onApply,
  });

  final CmsOffer offer;
  final double width;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return SizedBox(
      width: width,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onApply,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      if (offer.memberOnly) ...<Widget>[
                        Icon(
                          Icons.workspace_premium_outlined,
                          size: 12,
                          color: colors.secondary,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        offer.memberOnly ? 'MEMBERS ONLY' : 'OPEN TO ALL',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: offer.memberOnly
                              ? colors.secondary
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Text(
                    offer.title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Budgeted to exactly two lines so the footer never gets
                  // pushed out of the fixed-height card.
                  Expanded(
                    child: Text(
                      offer.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      _CodeTag(code: offer.promotionCode),
                      const Spacer(),
                      if (offer.termsUrl != null)
                        GestureDetector(
                          onTap: () => Navigator.of(context).pushNamed(
                            Routes.cmsPage,
                            arguments: CmsPageArgs(
                              slug: 'offer-terms',
                              title: 'Offer terms',
                              fallbackUrl: offer.termsUrl,
                            ),
                          ),
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 4,
                            ),
                            child: Text(
                              'Terms',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                                decoration: TextDecoration.underline,
                                decorationColor: colors.outlineVariant,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The promotion code, set as a tag rather than as body copy — it is the one
/// piece of the card a guest might read aloud or type somewhere else. Gold,
/// because applying it is the card's only action.
class _CodeTag extends StatelessWidget {
  const _CodeTag({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: theme.colorScheme.secondary.withAlpha(110)),
      ),
      child: Text(
        code,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}
