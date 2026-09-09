/// Money handled in *minor units* (cents), never doubles.
///
/// Floating point in a payment path is a defect waiting to happen: three
/// nights at 333.33 EUR must total 999.99, not 999.9899999999999. Every price
/// in this app - SynXis rates, cart totals, loyalty discounts - is an `int` of
/// minor units plus an ISO-4217 currency code.
class Money implements Comparable<Money> {
  const Money(this.minorUnits, this.currency);

  const Money.zero(this.currency) : minorUnits = 0;

  /// Parses the decimal amounts that vendor APIs send as strings or numbers.
  factory Money.fromApi(Object? amount, String currency) {
    if (amount == null) {
      return Money.zero(currency);
    }
    if (amount is int) {
      return Money((amount * 100), currency);
    }
    if (amount is num) {
      return Money((amount * 100).round(), currency);
    }
    final String text = amount.toString().trim();
    final double? parsed = double.tryParse(text);
    if (parsed == null) {
      return Money.zero(currency);
    }
    return Money((parsed * 100).round(), currency);
  }

  final int minorUnits;
  final String currency;

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money(minorUnits + other.minorUnits, currency);
  }

  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money(minorUnits - other.minorUnits, currency);
  }

  Money operator *(int factor) => Money(minorUnits * factor, currency);

  /// Percentage discount, rounded half-up to the nearest minor unit.
  Money percentage(double percent) =>
      Money((minorUnits * percent / 100).round(), currency);

  bool get isZero => minorUnits == 0;
  bool get isNegative => minorUnits < 0;

  double get asDouble => minorUnits / 100;

  void _assertSameCurrency(Money other) {
    assert(
      other.currency == currency,
      'Refusing to combine $currency with ${other.currency}. Multi-currency '
      'carts must be converted by the BFF, never on the client.',
    );
  }

  /// Deliberately dependency-free formatting so the POC has no `intl`
  /// version pin. Production would use `NumberFormat.simpleCurrency`.
  String format({bool withSymbol = true}) {
    final bool negative = minorUnits < 0;
    final int abs = minorUnits.abs();
    final String units = (abs ~/ 100).toString();
    final String cents = (abs % 100).toString().padLeft(2, '0');
    final String grouped = _group(units);
    final String symbol = withSymbol ? (symbols[currency] ?? '$currency ') : '';
    return '${negative ? '-' : ''}$symbol$grouped.$cents';
  }

  static String _group(String digits) {
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        out.write(',');
      }
      out.write(digits[i]);
    }
    return out.toString();
  }

  static const Map<String, String> symbols = <String, String>{
    'USD': r'$',
    'EUR': '€',
    'GBP': '£',
    'JPY': '¥',
    'CHF': 'CHF ',
    'AED': 'AED ',
  };

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  @override
  String toString() => '${format()} ($currency $minorUnits minor)';
}
