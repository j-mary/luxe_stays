import 'package:flutter_test/flutter_test.dart';
import 'package:luxe_stays/core/utils/money.dart';
import 'package:luxe_stays/domain/loyalty.dart';

void main() {
  const LoyaltyProgramRules rules = LoyaltyProgramRules();

  group('accrual preview', () {
    test('applies the tier multiplier to whole currency units', () {
      // 1,000.00 spend at 10 points per unit.
      const Money spend = Money(100000, 'USD');
      expect(
        rules.estimateAccrual(eligibleSpend: spend, tier: LoyaltyTier.classic),
        10000,
      );
      expect(
        rules.estimateAccrual(eligibleSpend: spend, tier: LoyaltyTier.gold),
        15000,
      );
      expect(
        rules.estimateAccrual(eligibleSpend: spend, tier: LoyaltyTier.platinum),
        20000,
      );
    });

    test('ignores the fractional part rather than rounding it up', () {
      // 99.99 earns on 99 units - the same rule Salesforce applies, and the
      // reason a client-side preview must floor rather than round.
      expect(
        rules.estimateAccrual(
          eligibleSpend: const Money(9999, 'USD'),
          tier: LoyaltyTier.classic,
        ),
        990,
      );
    });
  });

  group('redemption', () {
    test('refuses below the programme minimum', () {
      expect(
        rules.maxRedeemablePoints(
          balance: 1500,
          basketTotal: const Money(100000, 'USD'),
        ),
        0,
      );
    });

    test('snaps to the redemption increment', () {
      // 7,300 available, increment 500 -> 7,000.
      expect(
        rules.maxRedeemablePoints(
          balance: 7300,
          basketTotal: const Money(100000, 'USD'),
        ),
        7000,
      );
    });

    test('never exceeds the basket value', () {
      // A 120.00 basket is worth 12,000 points; the balance is larger.
      expect(
        rules.maxRedeemablePoints(
          balance: 48250,
          basketTotal: const Money(12000, 'USD'),
        ),
        12000,
      );
    });

    test('converts points to money at the programme rate', () {
      expect(rules.pointsToMoney(2500, 'EUR'), const Money(2500, 'EUR'));
    });
  });

  group('tiers', () {
    test('progress and nights-to-next-tier are consistent', () {
      const LoyaltyMember member = LoyaltyMember(
        memberId: 'm1',
        membershipNumber: 'LS-1',
        firstName: 'A',
        lastName: 'B',
        tier: LoyaltyTier.silver,
        pointsBalance: 0,
        qualifyingNightsThisYear: 20,
      );
      expect(member.tier.next, LoyaltyTier.gold);
      expect(member.nightsToNextTier, 5);
      expect(member.progressToNextTier, closeTo(0.8, 0.001));
    });

    test('the top tier has no next tier', () {
      const LoyaltyMember member = LoyaltyMember(
        memberId: 'm2',
        membershipNumber: 'LS-2',
        firstName: 'A',
        lastName: 'B',
        tier: LoyaltyTier.platinum,
        pointsBalance: 0,
        qualifyingNightsThisYear: 90,
      );
      expect(member.tier.next, isNull);
      expect(member.nightsToNextTier, isNull);
      expect(member.progressToNextTier, 1);
    });

    test('maps the Salesforce tier picklist, defaulting safely', () {
      expect(LoyaltyTier.fromSalesforce('Gold'), LoyaltyTier.gold);
      expect(LoyaltyTier.fromSalesforce('platinum'), LoyaltyTier.platinum);
      expect(LoyaltyTier.fromSalesforce('Titanium'), LoyaltyTier.classic);
      expect(LoyaltyTier.fromSalesforce(null), LoyaltyTier.classic);
    });
  });

  group('vouchers', () {
    test('a percentage voucher discounts the subtotal', () {
      final LoyaltyVoucher voucher = LoyaltyVoucher(
        id: 'v1',
        code: 'WELCOME10',
        name: 'Welcome reward',
        type: VoucherType.percentOff,
        percentOff: 10,
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );
      expect(
        voucher.discountOn(const Money(50000, 'USD')),
        const Money(5000, 'USD'),
      );
    });

    test('an expired voucher discounts nothing', () {
      final LoyaltyVoucher voucher = LoyaltyVoucher(
        id: 'v2',
        code: 'OLD',
        name: 'Expired',
        type: VoucherType.fixedAmount,
        valueMinor: 5000,
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(voucher.isUsable, isFalse);
      expect(voucher.discountOn(const Money(50000, 'USD')).isZero, isTrue);
    });

    test('a minimum-spend voucher does not apply below the threshold', () {
      final LoyaltyVoucher voucher = LoyaltyVoucher(
        id: 'v3',
        code: 'BIG',
        name: 'Big spender',
        type: VoucherType.fixedAmount,
        valueMinor: 10000,
        minimumSpendMinor: 100000,
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );
      expect(voucher.discountOn(const Money(50000, 'USD')).isZero, isTrue);
      expect(
        voucher.discountOn(const Money(150000, 'USD')),
        const Money(10000, 'USD'),
      );
    });
  });
}
