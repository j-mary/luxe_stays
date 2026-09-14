import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/error/failure.dart';
import '../../data/hotel_repository.dart';
import '../../domain/cart.dart';
import '../../domain/rate.dart';
import '../../domain/search.dart';
import '../../shared/widgets/app_snack_bar.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/section_heading.dart';
import '../account/session_controller.dart';
import '../cart/cart_controller.dart';
import 'search_controller.dart';
import 'widgets/filter_sheet.dart';
import 'widgets/hotel_card.dart';
import 'widgets/offers_strip.dart';
import 'widgets/stay_selector.dart';

/// Search + results.
///
/// The one screen where all four integrations are visible at once: SynXis
/// prices the results, the CMS supplies the headline on each card, Leonardo
/// supplies the photograph, and Salesforce decides whether member rates appear
/// at all.
class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  Future<void> _openFilters(BuildContext context, WidgetRef ref) async {
    final SearchState state = ref.read(searchProvider);
    final SearchFilters? updated = await showModalBottomSheet<SearchFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (BuildContext context) => FilterSheet(
        initial: state.query.filters,
        currency: state.query.currency,
      ),
    );
    if (updated != null) {
      ref.read(searchProvider.notifier).updateFilters(updated);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SearchState state = ref.watch(searchProvider);
    final HotelSearchController controller = ref.read(searchProvider.notifier);
    final Cart cart = ref.watch(cartProvider);
    final SessionState session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          // Set as a letterspaced serif wordmark rather than as an app-bar
          // title: the brand is the only thing in the chrome, so it should
          // read as a masthead.
          'LUXESTAYS',
          style: AppTheme.serif(size: 17, letterSpacing: 4.2),
        ),
        // A hairline instead of an elevation shadow. The masthead is separated
        // from the page by a rule, the same device used for every other
        // section break in the app.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refine',
            onPressed: () => _openFilters(context, ref),
            icon: Badge(
              isLabelVisible: state.query.filters.activeCount > 0,
              label: Text('${state.query.filters.activeCount}'),
              child: const Icon(Icons.tune_rounded),
            ),
          ),
          IconButton(
            tooltip: 'Cart',
            onPressed: () => Navigator.of(context).pushNamed(Routes.cart),
            icon: Badge(
              isLabelVisible: cart.lineCount > 0,
              label: Text('${cart.lineCount}'),
              child: const Icon(Icons.shopping_bag_outlined),
            ),
          ),
          IconButton(
            tooltip: session.isSignedIn ? 'Rewards' : 'Sign in',
            onPressed: () => Navigator.of(context).pushNamed(Routes.loyalty),
            icon: Icon(
              session.isSignedIn
                  ? Icons.workspace_premium_rounded
                  : Icons.person_outline_rounded,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => controller.search(forceRefresh: true),
        child: CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: StaySelector(
                query: state.query,
                destinations: demoDestinations,
                onDestinationChanged: controller.updateDestination,
                onStayChanged: controller.updateStay,
                onOccupancyChanged: controller.updateOccupancy,
                onSearch: controller.search,
              ),
            ),
            if (session.isSignedIn)
              SliverToBoxAdapter(child: _MemberBanner(session: session)),
            const SliverToBoxAdapter(child: OffersStrip()),
            ...state.results.when<List<Widget>>(
              loading: () => <Widget>[
                SliverList.builder(
                  itemCount: 4,
                  itemBuilder: (BuildContext context, int index) =>
                      const SkeletonCard(),
                ),
              ],
              error: (Object error, StackTrace stackTrace) => <Widget>[
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: FailureView(
                    failure: error is Failure
                        ? error
                        : ServerFailure(
                            developerMessage: error.toString(),
                            statusCode: 0,
                          ),
                    onRetry: () => controller.search(forceRefresh: true),
                  ),
                ),
              ],
              data: (List<HotelSearchResult> results) {
                if (results.isEmpty) {
                  return <Widget>[
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyView(
                        title: 'No availability',
                        message: 'Try different dates, or relax your filters.',
                        action: OutlinedButton(
                          onPressed: () => _openFilters(context, ref),
                          child: const Text('Adjust filters'),
                        ),
                      ),
                    ),
                  ];
                }
                return <Widget>[
                  SliverToBoxAdapter(
                    child: SectionHeading(
                      label:
                          '${results.length} PROPERT'
                          '${results.length == 1 ? 'Y' : 'IES'} AVAILABLE',
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: results.length,
                    itemBuilder: (BuildContext context, int index) {
                      final HotelSearchResult result = results[index];
                      return HotelCard(
                        result: result,
                        onTap: () => Navigator.of(context).pushNamed(
                          Routes.hotelDetail,
                          arguments: HotelDetailArgs(
                            hotelId: result.hotel.id,
                            hotelName: result.hotel.name,
                          ),
                        ),
                        onQuickAdd: (RoomOffer offer) {
                          ref
                              .read(cartProvider.notifier)
                              .add(hotel: result.hotel, offer: offer);
                          showAppSnackBar(
                            context,
                            '${result.hotel.name} added',
                            actionLabel: 'View cart',
                            onAction: () =>
                                Navigator.of(context).pushNamed(Routes.cart),
                          );
                        },
                      );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ];
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberBanner extends StatelessWidget {
  const _MemberBanner({required this.session});

  final SessionState session;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 11, 14, 11),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: colors.secondary, width: 2)),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.workspace_premium_outlined,
              size: 15,
              color: colors.secondary,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                '${session.tier.label.toUpperCase()} · '
                '${session.tier.memberRateDiscountPercent.toStringAsFixed(0)}% '
                'MEMBER RATES APPLIED',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
