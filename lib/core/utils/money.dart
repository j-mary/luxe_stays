class Money implements Comparable<Money> {
  const Money(this.minorUnits, this.currency);
  const Money.zero(this.currency) : minorUnits = 0;

  /// Parses the decimal amounts vendor APIs send as strings or numbers.
  ///
  /// Correctly handles currency decimal scales (e.g. JPY has 0 decimals,
  /// BHD has 3, USD/EUR have 2) and strips formatting commas from strings.
  factory Money.fromApi(Object? amount, String currency) {
    if (amount == null) return Money.zero(currency);
    final int factor = scaleFactorFor(currency);
    if (amount is int) return Money(amount * factor, currency);
    if (amount is num) return Money((amount * factor).round(), currency);

    final String sanitized = amount.toString().replaceAll(',', '').trim();
    final double? parsed = double.tryParse(sanitized);
    return parsed == null
        ? Money.zero(currency)
        : Money((parsed * factor).round(), currency);
  }

  /// Direct minor-unit constructor alias for clarity.
  factory Money.fromMinor(int minorUnits, String currency) =>
      Money(minorUnits, currency);

  final int minorUnits;
  final String currency;

  /// Number of decimal digits for this currency (e.g. JPY = 0, USD = 2, BHD = 3).
  int get decimals => decimalsFor(currency);

  /// The multiplier to convert between major and minor units (e.g. 100 for USD, 1 for JPY).
  int get scaleFactor => scaleFactorFor(currency);

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money(minorUnits + other.minorUnits, currency);
  }

  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money(minorUnits - other.minorUnits, currency);
  }

  Money operator *(num factor) =>
      Money((minorUnits * factor).round(), currency);

  Money operator /(num divisor) {
    if (divisor == 0) {
      throw ArgumentError.value(divisor, 'divisor', 'Cannot divide by zero');
    }
    return Money((minorUnits / divisor).round(), currency);
  }

  Money operator -() => Money(-minorUnits, currency);

  Money abs() => Money(minorUnits.abs(), currency);

  /// Percentage discount, rounded half-up to the nearest minor unit.
  Money percentage(double percent) =>
      Money((minorUnits * percent / 100).round(), currency);

  bool get isZero => minorUnits == 0;
  bool get isNegative => minorUnits < 0;
  double get asDouble => minorUnits / scaleFactor;

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  bool operator <(Money other) => compareTo(other) < 0;
  bool operator <=(Money other) => compareTo(other) <= 0;
  bool operator >(Money other) => compareTo(other) > 0;
  bool operator >=(Money other) => compareTo(other) >= 0;

  void _assertSameCurrency(Money other) {
    if (other.currency.trim().toUpperCase() != currency.trim().toUpperCase()) {
      throw ArgumentError(
        'Refusing to combine $currency with ${other.currency}. '
        'Multi-currency carts must be converted by the BFF, never on '
        'the client.',
      );
    }
  }

  /// Dependency-free formatting, supporting optional custom separators
  /// and correctly omitting decimals for zero-decimal currencies (like JPY).
  String format({
    bool withSymbol = true,
    String decimalSeparator = '.',
    String groupSeparator = ',',
  }) {
    final bool negative = minorUnits < 0;
    final int absVal = minorUnits.abs();
    final String code = currency.trim().toUpperCase();
    final String symbol = withSymbol ? (symbols[code] ?? '$code ') : '';

    if (decimals == 0) {
      final String units = absVal.toString();
      return '${negative ? '-' : ''}$symbol${_group(units, groupSeparator)}';
    }

    final int factor = scaleFactor;
    final String units = (absVal ~/ factor).toString();
    final String cents = (absVal % factor).toString().padLeft(decimals, '0');
    return '${negative ? '-' : ''}$symbol${_group(units, groupSeparator)}$decimalSeparator$cents';
  }

  static String _group(String digits, [String separator = ',']) {
    if (digits.length <= 3) return digits;
    final StringBuffer buffer = StringBuffer();
    final int remainder = digits.length % 3;
    if (remainder > 0) {
      buffer.write(digits.substring(0, remainder));
    }
    for (int i = remainder; i < digits.length; i += 3) {
      if (buffer.isNotEmpty) buffer.write(separator);
      buffer.write(digits.substring(i, i + 3));
    }
    return buffer.toString();
  }

  /// Returns the decimal digits for a currency code (defaults to 2).
  static int decimalsFor(String currency) =>
      _decimals[currency.trim().toUpperCase()] ?? 2;

  /// Returns the scale factor for a currency code (e.g. 1 for JPY, 100 for USD, 1000 for BHD).
  static int scaleFactorFor(String currency) {
    final int dec = decimalsFor(currency);
    switch (dec) {
      case 0:
        return 1;
      case 1:
        return 10;
      case 2:
        return 100;
      case 3:
        return 1000;
      default:
        int factor = 1;
        for (int i = 0; i < dec; i++) {
          factor *= 10;
        }
        return factor;
    }
  }

  static const Map<String, int> _decimals = <String, int>{
    // 0-decimal currencies
    'JPY': 0,
    'KRW': 0,
    'VND': 0,
    'CLP': 0,
    'PYG': 0,
    'UGX': 0,
    'BIF': 0,
    'DJF': 0,
    'GNF': 0,
    'KMF': 0,
    'RWF': 0,
    'XAF': 0,
    'XOF': 0,
    'XPF': 0,

    // 3-decimal currencies
    'BHD': 3,
    'KWD': 3,
    'OMR': 3,
    'JOD': 3,
    'TND': 3,
    'LYD': 3,
    'IQD': 3,
  };

  static const Map<String, String> symbols = <String, String>{
    'NGN': '₦',
    'USD': r'$',
    'EUR': '€',
    'GBP': '£',
    'JPY': '¥',
    'CHF': 'CHF ',
    'AED': 'AED ',
    'CAD': r'CA$',
    'AUD': r'A$',
    'KRW': '₩',
    'INR': '₹',
    'CNY': '¥',
    'SGD': r'S$',
  };

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.currency.toUpperCase() == currency.toUpperCase();

  @override
  int get hashCode => Object.hash(minorUnits, currency.toUpperCase());

  @override
  String toString() => format();
}
