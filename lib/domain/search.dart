import '../core/utils/date_x.dart';

/// Everything the guest chose on the search screen.
///
/// One object, because it is the cache key for the SynXis availability call,
/// the analytics payload, and the query string handed to the WebView booking
/// engine. Keeping it a single value type stops those three drifting apart.
class SearchQuery {
  const SearchQuery({
    required this.destination,
    required this.stay,
    required this.occupancy,
    this.filters = const SearchFilters(),
    this.currency = 'USD',
    this.promotionCode,
    this.corporateCode,
  });

  factory SearchQuery.initial() => SearchQuery(
        destination: const Destination(
          id: 'any',
          label: 'Anywhere',
          type: DestinationType.anywhere,
        ),
        stay: DateRange.nightsFrom(
          DateTime.now().addDays(21),
          2,
        ),
        occupancy: const Occupancy(),
      );

  final Destination destination;
  final DateRange stay;
  final Occupancy occupancy;
  final SearchFilters filters;
  final String currency;

  /// SynXis `promotionCode` - a public offer code.
  final String? promotionCode;

  /// SynXis `corporateCode` / negotiated-rate access code.
  final String? corporateCode;

  SearchQuery copyWith({
    Destination? destination,
    DateRange? stay,
    Occupancy? occupancy,
    SearchFilters? filters,
    String? currency,
    String? promotionCode,
    String? corporateCode,
  }) {
    return SearchQuery(
      destination: destination ?? this.destination,
      stay: stay ?? this.stay,
      occupancy: occupancy ?? this.occupancy,
      filters: filters ?? this.filters,
      currency: currency ?? this.currency,
      promotionCode: promotionCode ?? this.promotionCode,
      corporateCode: corporateCode ?? this.corporateCode,
    );
  }

  /// Stable cache key. Includes the filters because SynXis prices per
  /// rate-plan set, and excludes nothing that changes the price.
  String get cacheKey => <String>[
        destination.id,
        stay.checkIn.iso8601Date,
        stay.checkOut.iso8601Date,
        '${occupancy.adults}a${occupancy.children.length}c${occupancy.rooms}r',
        currency,
        promotionCode ?? '-',
        corporateCode ?? '-',
        filters.cacheKey,
      ].join('|');
}

enum DestinationType { anywhere, city, country, region, property, landmark }

class Destination {
  const Destination({
    required this.id,
    required this.label,
    required this.type,
    this.latitude,
    this.longitude,
    this.countryCode,
  });

  final String id;
  final String label;
  final DestinationType type;
  final double? latitude;
  final double? longitude;
  final String? countryCode;
}

class Occupancy {
  const Occupancy({
    this.adults = 2,
    this.children = const <int>[],
    this.rooms = 1,
  });

  final int adults;

  /// Child *ages*, not a count. Hotels price children by age band, and SynXis
  /// rejects an availability request that sends a count without ages.
  final List<int> children;
  final int rooms;

  int get totalGuests => adults + children.length;

  String get label {
    final StringBuffer b =
        StringBuffer('$adults adult${adults == 1 ? '' : 's'}');
    if (children.isNotEmpty) {
      b.write(', ${children.length} child${children.length == 1 ? '' : 'ren'}');
    }
    b.write(' · $rooms room${rooms == 1 ? '' : 's'}');
    return b.toString();
  }

  Occupancy copyWith({int? adults, List<int>? children, int? rooms}) =>
      Occupancy(
        adults: adults ?? this.adults,
        children: children ?? this.children,
        rooms: rooms ?? this.rooms,
      );
}

class SearchFilters {
  const SearchFilters({
    this.minStars = 0,
    this.maxNightlyRateMinor,
    this.amenities = const <String>{},
    this.mealPlans = const <MealPlan>{},
    this.freeCancellationOnly = false,
    this.memberRatesOnly = false,
    this.sort = SortOption.recommended,
  });

  final int minStars;
  final int? maxNightlyRateMinor;
  final Set<String> amenities;
  final Set<MealPlan> mealPlans;
  final bool freeCancellationOnly;

  /// Member-only rates are the commercial reason the loyalty programme exists:
  /// signed-in guests see inventory that anonymous guests do not.
  final bool memberRatesOnly;
  final SortOption sort;

  bool get isEmpty =>
      minStars == 0 &&
      maxNightlyRateMinor == null &&
      amenities.isEmpty &&
      mealPlans.isEmpty &&
      !freeCancellationOnly &&
      !memberRatesOnly;

  int get activeCount =>
      (minStars > 0 ? 1 : 0) +
      (maxNightlyRateMinor != null ? 1 : 0) +
      amenities.length +
      mealPlans.length +
      (freeCancellationOnly ? 1 : 0) +
      (memberRatesOnly ? 1 : 0);

  SearchFilters copyWith({
    int? minStars,
    int? maxNightlyRateMinor,
    bool clearMaxRate = false,
    Set<String>? amenities,
    Set<MealPlan>? mealPlans,
    bool? freeCancellationOnly,
    bool? memberRatesOnly,
    SortOption? sort,
  }) {
    return SearchFilters(
      minStars: minStars ?? this.minStars,
      maxNightlyRateMinor: clearMaxRate
          ? null
          : (maxNightlyRateMinor ?? this.maxNightlyRateMinor),
      amenities: amenities ?? this.amenities,
      mealPlans: mealPlans ?? this.mealPlans,
      freeCancellationOnly: freeCancellationOnly ?? this.freeCancellationOnly,
      memberRatesOnly: memberRatesOnly ?? this.memberRatesOnly,
      sort: sort ?? this.sort,
    );
  }

  String get cacheKey => <String>[
        's$minStars',
        'p${maxNightlyRateMinor ?? '-'}',
        'a${(amenities.toList()..sort()).join(',')}',
        'm${(mealPlans.map((MealPlan p) => p.name).toList()..sort()).join(',')}',
        freeCancellationOnly ? 'fc' : '-',
        memberRatesOnly ? 'mr' : '-',
        sort.name,
      ].join('/');
}

enum SortOption {
  recommended,
  priceLowToHigh,
  priceHighToLow,
  guestRating,
  starRating;

  String get label => switch (this) {
        SortOption.recommended => 'Recommended',
        SortOption.priceLowToHigh => 'Price: low to high',
        SortOption.priceHighToLow => 'Price: high to low',
        SortOption.guestRating => 'Guest rating',
        SortOption.starRating => 'Star rating',
      };
}

enum MealPlan {
  roomOnly,
  breakfast,
  halfBoard,
  fullBoard,
  allInclusive;

  String get label => switch (this) {
        MealPlan.roomOnly => 'Room only',
        MealPlan.breakfast => 'Breakfast included',
        MealPlan.halfBoard => 'Half board',
        MealPlan.fullBoard => 'Full board',
        MealPlan.allInclusive => 'All inclusive',
      };

  /// SynXis sends OTA-style meal-plan codes on the rate plan.
  static MealPlan fromCode(String? code) => switch (code?.toUpperCase()) {
        'BB' || 'BREAKFAST' => MealPlan.breakfast,
        'HB' || 'HALFBOARD' => MealPlan.halfBoard,
        'FB' || 'FULLBOARD' => MealPlan.fullBoard,
        'AI' || 'ALLINCLUSIVE' => MealPlan.allInclusive,
        _ => MealPlan.roomOnly,
      };
}
