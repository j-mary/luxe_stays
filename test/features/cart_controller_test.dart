import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luxe_stays/core/utils/date_x.dart';
import 'package:luxe_stays/core/utils/money.dart';
import 'package:luxe_stays/domain/cart.dart';
import 'package:luxe_stays/domain/hotel.dart';
import 'package:luxe_stays/domain/loyalty.dart';
import 'package:luxe_stays/domain/rate.dart';
import 'package:luxe_stays/domain/search.dart';
import 'package:luxe_stays/features/cart/cart_controller.dart';

Hotel _hotel(String id) => Hotel(
  id: id,
  chainId: '12345',
  name: 'Hotel $id',
  city: 'Paris',
  country: 'FR',
  starRating: 5,
);

RoomOffer _offer({
  required String hotelId,
  String ratePlan = 'BAR',
  int nightlyMinor = 30000,
  int nights = 2,
  bool memberRate = false,
}) {
  final DateTime checkIn = DateTime(2026, 11, 12);
  return RoomOffer(
    offerId: '$hotelId:DLX:$ratePlan:2026-11-12',
    hotelId: hotelId,
    roomType: const RoomType(code: 'DLX', name: 'Deluxe room'),
    ratePlanCode: ratePlan,
    ratePlanName: 'Best available',
    stay: DateRange.nightsFrom(checkIn, nights),
    occupancy: const Occupancy(),
    nightlyRates: <DateTime, Money>{
      for (int i = 0; i < nights; i++)
        checkIn.addDays(i): Money(nightlyMinor, 'USD'),
    },
    taxesAndFees: const Money(5000, 'USD'),
    cancellationPolicy: const CancellationPolicy(description: 'Free'),
    quotedAt: DateTime.now(),
    isMemberRate: memberRate,
  );
}

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  test('adds a line and totals it', () {
    final CartController controller = container.read(cartProvider.notifier);
    controller.add(
      hotel: _hotel('H-1'),
      offer: _offer(hotelId: 'H-1'),
    );

    final Cart cart = container.read(cartProvider);
    expect(cart.lineCount, 1);
    expect(cart.roomNights, 2);
    // 2 x 300.00 + 50.00 tax
    expect(cart.subtotal, const Money(65000, 'USD'));
  });

  test('refuses to add the same offer twice', () {
    final CartController controller = container.read(cartProvider.notifier);
    final RoomOffer offer = _offer(hotelId: 'H-1');
    controller.add(hotel: _hotel('H-1'), offer: offer);
    controller.add(hotel: _hotel('H-1'), offer: offer);
    expect(container.read(cartProvider).lineCount, 1);
  });

  test('holds lines from different properties', () {
    final CartController controller = container.read(cartProvider.notifier);
    controller.add(
      hotel: _hotel('H-1'),
      offer: _offer(hotelId: 'H-1'),
    );
    controller.add(
      hotel: _hotel('H-2'),
      offer: _offer(hotelId: 'H-2', nightlyMinor: 45000),
    );
    final Cart cart = container.read(cartProvider);
    expect(cart.lineCount, 2);
    expect(cart.subtotal, const Money(160000, 'USD'));
  });

  test('bumps the revision on every mutation so idempotency keys change', () {
    final CartController controller = container.read(cartProvider.notifier);
    expect(container.read(cartProvider).revision, 0);
    controller.add(
      hotel: _hotel('H-1'),
      offer: _offer(hotelId: 'H-1'),
    );
    expect(container.read(cartProvider).revision, 1);
    controller.remove(container.read(cartProvider).items.first.lineId);
    expect(container.read(cartProvider).revision, greaterThan(1));
  });

  test('a blocked line prevents checkout', () {
    final CartController controller = container.read(cartProvider.notifier);
    controller.add(
      hotel: _hotel('H-1'),
      offer: _offer(hotelId: 'H-1'),
    );
    expect(container.read(cartProvider).canCheckout, isTrue);

    controller.replaceItems(
      container
          .read(cartProvider)
          .items
          .map(
            (CartItem item) =>
                item.copyWith(status: CartLineStatus.priceChanged),
          )
          .toList(),
    );
    expect(container.read(cartProvider).canCheckout, isFalse);
  });

  test('signed-out guests cannot redeem points', () {
    final CartController controller = container.read(cartProvider.notifier);
    controller.add(
      hotel: _hotel('H-1'),
      offer: _offer(hotelId: 'H-1'),
    );
    expect(controller.maxRedeemablePoints(), 0);
  });

  test('a voucher discounts the total but never below zero', () {
    final CartController controller = container.read(cartProvider.notifier);
    controller.add(
      hotel: _hotel('H-1'),
      offer: _offer(hotelId: 'H-1'),
    );
    controller.applyVoucher(
      LoyaltyVoucher(
        id: 'v1',
        code: 'HUGE',
        name: 'Oversized reward',
        type: VoucherType.fixedAmount,
        valueMinor: 999999,
        expiresAt: DateTime.now().add(const Duration(days: 10)),
      ),
    );

    const LoyaltyProgramRules rules = LoyaltyProgramRules();
    final Cart cart = container.read(cartProvider);
    expect(cart.total(rules).isZero, isTrue);
    expect(cart.total(rules).isNegative, isFalse);
  });

  test('derived totals include an accrual estimate', () {
    final CartController controller = container.read(cartProvider.notifier);
    controller.add(
      hotel: _hotel('H-1'),
      offer: _offer(hotelId: 'H-1'),
    );
    final CartTotals totals = container.read(cartTotalsProvider);
    expect(totals.subtotal, const Money(65000, 'USD'));
    // 650 whole units x 10 points, Classic multiplier.
    expect(totals.estimatedPointsEarned, 6500);
  });

  test('clearing the cart resets loyalty adjustments and issues a new id', () {
    final CartController controller = container.read(cartProvider.notifier);
    final String firstId = container.read(cartProvider).id;
    controller.add(
      hotel: _hotel('H-1'),
      offer: _offer(hotelId: 'H-1'),
    );
    controller.clear();
    final Cart cart = container.read(cartProvider);
    expect(cart.isEmpty, isTrue);
    expect(cart.appliedVoucher, isNull);
    expect(cart.id, isNot(firstId));
  });
}
