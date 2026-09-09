/// Date helpers for a booking domain.
///
/// Hotel stays are *calendar-date* concepts, not instants: a 2-night stay from
/// 12 Mar is the same stay whether the guest's phone is in Lagos or Zurich.
/// Everything below therefore works on date-only `DateTime`s in local time and
/// serialises to `yyyy-MM-dd`, which is exactly what SynXis expects.
extension DateOnlyX on DateTime {
  DateTime get dateOnly => DateTime(year, month, day);

  String get iso8601Date => '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  bool isSameDate(DateTime other) =>
      year == other.year && month == other.month && day == other.day;

  DateTime addDays(int days) => DateTime(year, month, day + days);
}

/// An inclusive-exclusive stay: [checkIn, checkOut).
class DateRange {
  DateRange(DateTime checkIn, DateTime checkOut)
      : checkIn = checkIn.dateOnly,
        checkOut = checkOut.dateOnly {
    assert(
      this.checkOut.isAfter(this.checkIn),
      'Check-out must be after check-in (a same-day stay is not a stay).',
    );
  }

  factory DateRange.nightsFrom(DateTime start, int nights) =>
      DateRange(start, start.addDays(nights));

  final DateTime checkIn;
  final DateTime checkOut;

  int get nights => checkOut.difference(checkIn).inDays;

  /// Each date the guest is *in house* (check-out day excluded) - the set of
  /// dates a nightly rate is quoted for.
  List<DateTime> get stayDates => List<DateTime>.generate(
        nights,
        (int i) => checkIn.addDays(i),
        growable: false,
      );

  String get label => '${checkIn.iso8601Date} → ${checkOut.iso8601Date}';

  @override
  bool operator ==(Object other) =>
      other is DateRange &&
      other.checkIn.isSameDate(checkIn) &&
      other.checkOut.isSameDate(checkOut);

  @override
  int get hashCode => Object.hash(checkIn, checkOut);

  @override
  String toString() => label;
}

/// A short, human-readable formatter used on cards and confirmations.
String formatShortDate(DateTime date) {
  const List<String> months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
