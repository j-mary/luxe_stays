import 'package:flutter_test/flutter_test.dart';
import 'package:luxe_stays/core/utils/money.dart';

void main() {
  group('Money', () {
    test('adds without floating-point drift', () {
      // The canonical failure: 3 x 333.33 in doubles gives 999.9899999999999.
      const Money night = Money(33333, 'EUR');
      final Money total = night + night + night;
      expect(total.minorUnits, 99999);
      expect(total.format(), '€999.99');
    });

    test('parses vendor amounts from numbers and strings alike', () {
      // SynXis sends decimals as numbers, Salesforce sometimes as strings.
      expect(Money.fromApi(120.5, 'USD').minorUnits, 12050);
      expect(Money.fromApi('120.50', 'USD').minorUnits, 12050);
      expect(Money.fromApi(120, 'USD').minorUnits, 12000);
      expect(Money.fromApi(null, 'USD').minorUnits, 0);
      expect(Money.fromApi('not a number', 'USD').minorUnits, 0);
      expect(Money.fromApi('1,234.56', 'NGN').minorUnits, 123456);
    });

    test('rounds half-up on percentage discounts', () {
      // 12% of 10.05 is 1.206 -> 1.21, not 1.20.
      expect(const Money(1005, 'USD').percentage(12).minorUnits, 121);
    });

    test('formats with thousands separators and the right symbol', () {
      expect(const Money(123456789, 'USD').format(), r'$1,234,567.89');
      expect(const Money(-4500, 'GBP').format(), '-£45.00');
      expect(const Money(999, 'CHF').format(), 'CHF 9.99');
      expect(const Money(1000, 'NGN').format(), '₦10.00');
      // An unknown currency falls back to the ISO code rather than guessing.
      expect(const Money(1000, 'ZZZ').format(), 'ZZZ 10.00');
    });

    test('uses ISO currency decimal scales', () {
      expect(Money.fromApi(120, 'JPY').minorUnits, 120);
      expect(const Money(120, 'JPY').format(), '¥120');
      expect(Money.fromApi('1.234', 'BHD').minorUnits, 1234);
      expect(const Money(1234, 'BHD').format(), 'BHD 1.234');
    });

    test('supports arithmetic, comparison and custom separators', () {
      const Money amount = Money(123456, 'NGN');
      expect((amount / 2).format(), '₦617.28');
      expect((amount * 1.5).format(), '₦1,851.84');
      expect((-amount).abs(), amount);
      expect(amount > const Money(100000, 'ngn'), isTrue);
      expect(
        amount.format(decimalSeparator: ',', groupSeparator: '.'),
        '₦1.234,56',
      );
    });

    test('rejects cross-currency arithmetic in every build mode', () {
      expect(
        () => const Money(100, 'NGN') + const Money(100, 'USD'),
        throwsArgumentError,
      );
      expect(() => const Money(100, 'NGN') / 0, throwsArgumentError);
    });

    test('value equality lets offers de-duplicate', () {
      expect(const Money(100, 'USD'), const Money(100, 'USD'));
      expect(const Money(100, 'ngn'), const Money(100, 'NGN'));
      expect(const Money(100, 'USD') == const Money(100, 'EUR'), isFalse);
    });
  });
}
