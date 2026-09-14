import '../core/utils/money.dart';
import 'rate.dart';

/// Who is staying, and how to reach them.
///
/// Kept separate from any vendor payload: SynXis wants an OTA-shaped
/// `Guest` block, Salesforce wants a `Contact`, and the CMS wants nothing at
/// all. One domain type, three mappers.
class GuestDetails {
  const GuestDetails({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    this.countryCode = 'US',
    this.membershipNumber,
    this.arrivalTime,
    this.specialRequests = '',
    this.marketingOptIn = false,
  });

  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String countryCode;
  final String? membershipNumber;
  final String? arrivalTime;
  final String specialRequests;

  /// Consent is captured here and propagated to Salesforce Marketing Cloud.
  /// It is never defaulted to true - see `docs/11-SECURITY.md`.
  final bool marketingOptIn;

  String get fullName => '$firstName $lastName';

  bool get isValid =>
      firstName.trim().length >= 2 &&
      lastName.trim().length >= 2 &&
      _emailPattern.hasMatch(email.trim()) &&
      phone.trim().length >= 6;

  static final RegExp _emailPattern = RegExp(
    r'^[\w.!#$%&*+/=?^`{|}~-]+@[\w-]+(\.[\w-]+)+$',
  );

  GuestDetails copyWith({
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    String? membershipNumber,
    String? arrivalTime,
    String? specialRequests,
    bool? marketingOptIn,
  }) {
    return GuestDetails(
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      countryCode: countryCode,
      membershipNumber: membershipNumber ?? this.membershipNumber,
      arrivalTime: arrivalTime ?? this.arrivalTime,
      specialRequests: specialRequests ?? this.specialRequests,
      marketingOptIn: marketingOptIn ?? this.marketingOptIn,
    );
  }
}

/// The server-created intent that the hosted payment page is opened against.
///
/// The app never sees a card number. It receives an intent id plus a URL, opens
/// that URL in a WebView, and waits for the bridge to report a result. This is
/// what keeps the handset out of PCI-DSS scope - see `docs/11-SECURITY.md`.
class PaymentIntent {
  const PaymentIntent({
    required this.intentId,
    required this.amount,
    required this.hostedPageUrl,
    required this.returnUrl,
    required this.expiresAt,
    this.provider = 'mock-psp',
  });

  final String intentId;
  final Money amount;
  final String hostedPageUrl;

  /// Deep-link the hosted page redirects to on completion. The WebView
  /// intercepts it rather than letting it navigate.
  final String returnUrl;
  final DateTime expiresAt;
  final String provider;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// What the payment WebView reported back over the bridge.
class PaymentResult {
  const PaymentResult({
    required this.intentId,
    required this.status,
    this.authorizationCode,
    this.declineReason,
    this.last4,
    this.brand,
    this.threeDsPerformed = false,
  });

  final String intentId;
  final PaymentStatus status;
  final String? authorizationCode;
  final String? declineReason;

  /// Only ever the last four digits, and only for display on the confirmation.
  final String? last4;
  final String? brand;
  final bool threeDsPerformed;

  bool get isAuthorized => status == PaymentStatus.authorized;
}

enum PaymentStatus { authorized, declined, cancelled, pending, failed }

/// A confirmed reservation, as returned by SynXis.
class Reservation {
  const Reservation({
    required this.confirmationNumber,
    required this.hotelId,
    required this.hotelName,
    required this.offer,
    required this.guest,
    required this.total,
    required this.createdAt,
    this.crsReservationId,
    this.status = ReservationStatus.confirmed,
    this.pointsEarned = 0,
    this.pointsRedeemed = 0,
    this.paymentLast4,
    this.itineraryUrl,
  });

  /// The number the guest quotes at the desk.
  final String confirmationNumber;

  /// SynXis's own internal id, used for modify/cancel calls.
  final String? crsReservationId;
  final String hotelId;
  final String hotelName;
  final RoomOffer offer;
  final GuestDetails guest;
  final Money total;
  final DateTime createdAt;
  final ReservationStatus status;

  /// Posted to Salesforce after the CRS confirms. Zero until the accrual
  /// journal succeeds - loyalty must never gate the booking itself.
  final int pointsEarned;
  final int pointsRedeemed;
  final String? paymentLast4;

  /// A CMS-rendered itinerary page, opened in a WebView from the confirmation
  /// screen and from the "My trips" list.
  final String? itineraryUrl;

  Reservation copyWith({
    ReservationStatus? status,
    int? pointsEarned,
    int? pointsRedeemed,
    String? itineraryUrl,
  }) {
    return Reservation(
      confirmationNumber: confirmationNumber,
      crsReservationId: crsReservationId,
      hotelId: hotelId,
      hotelName: hotelName,
      offer: offer,
      guest: guest,
      total: total,
      createdAt: createdAt,
      status: status ?? this.status,
      pointsEarned: pointsEarned ?? this.pointsEarned,
      pointsRedeemed: pointsRedeemed ?? this.pointsRedeemed,
      paymentLast4: paymentLast4,
      itineraryUrl: itineraryUrl ?? this.itineraryUrl,
    );
  }
}

enum ReservationStatus {
  confirmed,
  pending,
  cancelled,
  modified,
  noShow;

  String get label => switch (this) {
    ReservationStatus.confirmed => 'Confirmed',
    ReservationStatus.pending => 'Pending',
    ReservationStatus.cancelled => 'Cancelled',
    ReservationStatus.modified => 'Modified',
    ReservationStatus.noShow => 'No show',
  };
}

/// The outcome of the whole checkout orchestration - one reservation per cart
/// line, plus whatever the loyalty post-processing managed to do.
class BookingOutcome {
  const BookingOutcome({
    required this.reservations,
    required this.failures,
    this.pointsEarned = 0,
    this.pointsRedeemed = 0,
    this.loyaltyPostingDeferred = false,
  });

  final List<Reservation> reservations;

  /// Cart lines that could not be booked, keyed by line id with a message.
  final Map<String, String> failures;
  final int pointsEarned;
  final int pointsRedeemed;

  /// True when the reservations succeeded but Salesforce was unreachable; the
  /// accrual is queued for retry rather than shown as a failed booking.
  final bool loyaltyPostingDeferred;

  bool get isCompleteSuccess => failures.isEmpty && reservations.isNotEmpty;
  bool get isPartial => failures.isNotEmpty && reservations.isNotEmpty;
}
