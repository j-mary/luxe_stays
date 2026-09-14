import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luxe_stays/app/providers.dart';
import 'package:luxe_stays/core/utils/date_x.dart';
import 'package:luxe_stays/core/utils/money.dart';
import 'package:luxe_stays/data/hotel_repository.dart';
import 'package:luxe_stays/domain/hotel.dart';
import 'package:luxe_stays/domain/media.dart';
import 'package:luxe_stays/domain/rate.dart';
import 'package:luxe_stays/domain/search.dart';
import 'package:luxe_stays/features/search/widgets/hotel_card.dart';
import 'package:luxe_stays/integrations/leonardo/media_provider.dart';

/// Widget tests run with the media provider overridden by a fixture, so no
/// screen in this suite ever touches the network. That override is only
/// possible because widgets depend on the `MediaProvider` interface rather than
/// on a Leonardo client.
const MediaAsset _asset = MediaAsset(
  id: 'a1',
  baseUrl: 'https://example.test/a1.png',
  category: MediaCategory.exterior,
  altText: 'Facade',
  isHero: true,
);

RoomOffer _offer({
  int nightlyMinor = 30000,
  bool memberRate = false,
  int? roomsRemaining,
  int? publicTotalMinor,
}) {
  final DateTime checkIn = DateTime(2026, 11, 12);
  return RoomOffer(
    offerId: 'H-1:DLX:BAR:2026-11-12',
    hotelId: 'H-1',
    roomType: const RoomType(code: 'DLX', name: 'Deluxe room'),
    ratePlanCode: 'BAR',
    ratePlanName: 'Best available rate',
    stay: DateRange.nightsFrom(checkIn, 2),
    occupancy: const Occupancy(),
    nightlyRates: <DateTime, Money>{
      checkIn: Money(nightlyMinor, 'USD'),
      checkIn.addDays(1): Money(nightlyMinor, 'USD'),
    },
    taxesAndFees: const Money(0, 'USD'),
    cancellationPolicy: const CancellationPolicy(description: 'Free'),
    quotedAt: DateTime.now(),
    isMemberRate: memberRate,
    roomsRemaining: roomsRemaining,
    strikeThroughTotal: publicTotalMinor == null
        ? null
        : Money(publicTotalMinor, 'USD'),
  );
}

HotelSearchResult _result({
  HotelEditorial? editorial,
  List<MediaAsset> gallery = const <MediaAsset>[_asset],
  List<RoomOffer>? offers,
}) {
  return HotelSearchResult(
    hotel: Hotel(
      id: 'H-1',
      chainId: '12345',
      name: 'Maison Rivoli',
      city: 'Paris',
      country: 'FR',
      starRating: 5,
      gallery: gallery,
      editorial: editorial,
    ),
    offers: offers ?? <RoomOffer>[_offer()],
  );
}

Future<void> _pump(WidgetTester tester, HotelSearchResult result) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        mediaProviderProvider.overrideWithValue(
          const StaticMediaProvider(<String, List<MediaAsset>>{
            'H-1': <MediaAsset>[_asset],
          }),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HotelCard(result: result, onTap: () {}),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders name, location and the lead-in nightly price', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _result());
    await tester.pump();

    expect(find.text('Maison Rivoli'), findsOneWidget);
    // The card sets the location as a letterspaced overline, so the rendered
    // string is upper-cased at the call site rather than in the model.
    expect(find.text('PARIS, FR'), findsOneWidget);
    expect(find.text(r'$300.00'), findsOneWidget);
    expect(find.textContaining('total · 2 nights'), findsOneWidget);
  });

  testWidgets('renders without CMS content - content is never load-bearing', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _result());
    await tester.pump();

    // No editorial headline, but the card is still complete and bookable.
    expect(find.text('Maison Rivoli'), findsOneWidget);
    expect(find.byType(HotelCard), findsOneWidget);
  });

  testWidgets('shows the CMS headline when content has resolved', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      _result(
        editorial: const HotelEditorial(
          headline: 'A courtyard hotel one street from the Tuileries',
          body: 'Eighteen rooms.',
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('A courtyard hotel one street from the Tuileries'),
      findsOneWidget,
    );
  });

  testWidgets('badges member rates and low inventory', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      _result(offers: <RoomOffer>[_offer(memberRate: true, roomsRemaining: 2)]),
    );
    await tester.pump();

    expect(find.text('MEMBER RATE'), findsOneWidget);
    // The remaining-rooms count is part of the single total line, not its
    // own Text, so match on a substring.
    expect(find.textContaining('2 left'), findsOneWidget);
  });

  testWidgets('shows the saving against the public rate', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      _result(
        offers: <RoomOffer>[_offer(memberRate: true, publicTotalMinor: 70000)],
      ),
    );
    await tester.pump();

    // 700.00 public vs 600.00 member = 100.00 saved.
    expect(find.text(r'Saves $100.00 on the public rate'), findsOneWidget);
  });

  testWidgets('handles a property with no availability', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _result(offers: <RoomOffer>[]));
    await tester.pump();

    expect(find.text('No availability for these dates'), findsOneWidget);
  });
}
