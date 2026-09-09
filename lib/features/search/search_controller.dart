import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/analytics/analytics.dart';
import '../../core/error/failure.dart';
import '../../core/result.dart';
import '../../core/utils/date_x.dart';
import '../../data/hotel_repository.dart';
import '../../domain/search.dart';
import '../account/session_controller.dart';

class SearchState {
  const SearchState({
    required this.query,
    this.results = const AsyncValue<List<HotelSearchResult>>.loading(),
    this.lastSearchedAt,
  });

  final SearchQuery query;
  final AsyncValue<List<HotelSearchResult>> results;
  final DateTime? lastSearchedAt;

  SearchState copyWith({
    SearchQuery? query,
    AsyncValue<List<HotelSearchResult>>? results,
    DateTime? lastSearchedAt,
  }) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      lastSearchedAt: lastSearchedAt ?? this.lastSearchedAt,
    );
  }
}

/// Owns the search query and its results.
///
/// Note what it does *not* do: it never talks to SynXis, the CMS or Leonardo
/// directly. It calls one method on [HotelRepository] and stores an
/// `AsyncValue`. That keeps the multi-vendor fan-out testable without a widget
/// tree, and keeps this class small enough to read in one sitting.
class HotelSearchController extends Notifier<SearchState> {
  @override
  SearchState build() {
    // React to sign-in/sign-out: member rates change the result set, so the
    // search must be re-run rather than showing stale public pricing.
    ref.listen<SessionState>(sessionProvider,
        (SessionState? previous, SessionState next) {
      if (previous?.membershipNumber != next.membershipNumber &&
          state.lastSearchedAt != null) {
        unawaited(search(forceRefresh: true));
      }
    });
    // Run the first search immediately. The screen opens on results rather
    // than on an empty form, because `results` starts as AsyncValue.loading()
    // and nothing else would ever resolve it — the skeletons would sit there
    // until the guest happened to press Search.
    //
    // Deferred with a microtask because a Notifier may not mutate its own
    // state while `build()` is still running.
    bool disposed = false;
    ref.onDispose(() => disposed = true);
    unawaited(Future<void>.microtask(() {
      if (!disposed) {
        unawaited(search());
      }
    }));

    return SearchState(query: SearchQuery.initial());
  }

  void updateQuery(SearchQuery query) {
    state = state.copyWith(query: query);
  }

  void updateFilters(SearchFilters filters) {
    state = state.copyWith(query: state.query.copyWith(filters: filters));
    // Filtering is applied over the cached availability response, so this is
    // effectively free - no extra CRS shop request.
    unawaited(search());
  }

  void updateDestination(Destination destination) {
    state =
        state.copyWith(query: state.query.copyWith(destination: destination));
  }

  void updateStay(DateRange stay) {
    state = state.copyWith(query: state.query.copyWith(stay: stay));
  }

  void updateOccupancy(Occupancy occupancy) {
    state = state.copyWith(query: state.query.copyWith(occupancy: occupancy));
  }

  void applyPromotionCode(String? code) {
    state = state.copyWith(
      query: state.query.copyWith(
        promotionCode: (code == null || code.isEmpty) ? null : code,
      ),
    );
  }

  Future<void> search({bool forceRefresh = false}) async {
    final SearchQuery query = state.query;
    state = state.copyWith(
      results: const AsyncValue<List<HotelSearchResult>>.loading(),
    );

    ref.read(analyticsProvider).event(
      AnalyticsEvents.searchPerformed,
      parameters: <String, Object?>{
        'destination': query.destination.id,
        'nights': query.stay.nights,
        'adults': query.occupancy.adults,
        'children': query.occupancy.children.length,
        'filters': query.filters.activeCount,
        'member': ref.read(sessionProvider).isSignedIn,
      },
    );

    final Result<List<HotelSearchResult>> result =
        await ref.read(hotelRepositoryProvider).search(
              query,
              membershipNumber: ref.read(sessionProvider).membershipNumber,
              forceRefresh: forceRefresh,
            );

    state = state.copyWith(
      lastSearchedAt: DateTime.now(),
      results: result.fold<AsyncValue<List<HotelSearchResult>>>(
        (List<HotelSearchResult> data) =>
            AsyncValue<List<HotelSearchResult>>.data(data),
        (Failure failure) => AsyncValue<List<HotelSearchResult>>.error(
          failure,
          StackTrace.current,
        ),
      ),
    );
  }
}

/// Named `HotelSearchController`, not `SearchController`: Flutter's material
/// library exports its own `SearchController` (for `SearchAnchor`), and both
/// are in scope in any screen that imports `material.dart`.
final NotifierProvider<HotelSearchController, SearchState> searchProvider =
    NotifierProvider<HotelSearchController, SearchState>(
  HotelSearchController.new,
);

/// Destinations offered on the search screen.
///
/// In production this list comes from the CMS (marketing curates it) with the
/// ids matching SynXis destination codes. Hard-coded here so the POC runs
/// without content being authored first.
const List<Destination> demoDestinations = <Destination>[
  Destination(id: 'any', label: 'Anywhere', type: DestinationType.anywhere),
  Destination(
    id: 'PAR',
    label: 'Paris',
    type: DestinationType.city,
    countryCode: 'FR',
  ),
  Destination(
    id: 'KYO',
    label: 'Kyoto',
    type: DestinationType.city,
    countryCode: 'JP',
  ),
  Destination(
    id: 'NYC',
    label: 'New York',
    type: DestinationType.city,
    countryCode: 'US',
  ),
  Destination(
    id: 'DXB',
    label: 'Dubai',
    type: DestinationType.city,
    countryCode: 'AE',
  ),
  Destination(
    id: 'CPT',
    label: 'Cape Town',
    type: DestinationType.city,
    countryCode: 'ZA',
  ),
];
