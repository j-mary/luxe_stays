import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../integrations/cms/cms_models.dart';
import '../../home/offers_provider.dart';
import '../search_controller.dart';

/// CMS-authored offers. Tapping one applies its promotion code to the search.
class OffersStrip extends ConsumerWidget {
  const OffersStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<CmsOffer>> offers = ref.watch(offersProvider);

    return offers.maybeWhen<Widget>(
      orElse: () => const SizedBox.shrink(),
      data: (List<CmsOffer> list) {
        if (list.isEmpty) {
          return const SizedBox.shrink();
        }
        final ThemeData theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text('Offers', style: theme.textTheme.titleMedium),
            ),
            SizedBox(
              height: 116,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (BuildContext context, int index) {
                  final CmsOffer offer = list[index];
                  return SizedBox(
                    width: 260,
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          ref
                              .read(searchProvider.notifier)
                              .applyPromotionCode(offer.promotionCode);
                          ref.read(searchProvider.notifier).search(
                                forceRefresh: true,
                              );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      offer.title,
                                      style: theme.textTheme.titleSmall,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (offer.memberOnly)
                                    Icon(
                                      Icons.workspace_premium_rounded,
                                      size: 14,
                                      color: theme.colorScheme.primary,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Expanded(
                                child: Text(
                                  offer.subtitle,
                                  style: theme.textTheme.bodySmall,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Row(
                                children: <Widget>[
                                  Text(
                                    'Code ${offer.promotionCode}',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (offer.termsUrl != null)
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pushNamed(
                                        Routes.cmsPage,
                                        arguments: CmsPageArgs(
                                          slug: 'offer-terms',
                                          title: 'Offer terms',
                                          fallbackUrl: offer.termsUrl,
                                        ),
                                      ),
                                      child: const Text('Terms'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
