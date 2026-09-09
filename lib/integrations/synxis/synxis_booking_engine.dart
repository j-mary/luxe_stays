import '../../core/utils/date_x.dart';
import '../../domain/rate.dart';
import '../../domain/search.dart';

/// Builds URLs for the **SynXis Booking Engine** web flow and interprets the
/// deep links it hands back.
///
/// Why a WebView at all, when we have the REST API?
///
/// Because parts of the booking journey are owned by the CRS and change without
/// an app release: chain-specific upsell modules, regional consent and tax
/// disclosures, packages/add-ons configured per property, and the
/// certification-sensitive payment step. Re-implementing those natively means
/// re-certifying with Sabre on every change. So the app is *native where it
/// competes* (search, filtering, cart, loyalty) and *web where it must comply*.
///
/// The contract with the web layer is:
///  * we pass state in the query string, signed by our BFF;
///  * the page talks back over the JS bridge (`docs/02-WEBVIEW-BRIDGE.md`);
///  * terminal states arrive as `luxestays://` deep links which the
///    `NavigationDelegate` intercepts and never actually navigates to.
class SynxisBookingEngine {
  const SynxisBookingEngine({
    required this.baseUrl,
    required this.chainId,
  });

  final String baseUrl;
  final String chainId;

  /// Custom scheme the WebView intercepts. Registering it as the return URL
  /// means the web flow can terminate without ever loading another page.
  static const String deepLinkScheme = 'luxestays';

  /// Deep-link hosts, one per terminal state.
  static const String hostBookingComplete = 'booking-complete';
  static const String hostBookingCancelled = 'booking-cancelled';
  static const String hostBookingFailed = 'booking-failed';

  /// The full booking flow, starting at the room-select step.
  Uri bookingUrl({
    required String hotelId,
    required SearchQuery query,
    String? roomTypeCode,
    String? ratePlanCode,
    String? membershipNumber,
    String locale = 'en-US',
    String? sessionToken,
  }) {
    return Uri.parse(baseUrl).replace(
      queryParameters: <String, String>{
        'chain': chainId,
        'hotel': hotelId,
        'arrive': query.stay.checkIn.iso8601Date,
        'depart': query.stay.checkOut.iso8601Date,
        'adult': query.occupancy.adults.toString(),
        'rooms': query.occupancy.rooms.toString(),
        if (query.occupancy.children.isNotEmpty)
          'childages': query.occupancy.children.join(','),
        'currency': query.currency,
        'locale': locale,
        if (roomTypeCode != null) 'room': roomTypeCode,
        if (ratePlanCode != null) 'rate': ratePlanCode,
        if (query.promotionCode != null) 'promo': query.promotionCode!,
        if (query.corporateCode != null) 'corporate': query.corporateCode!,
        if (membershipNumber != null) 'member': membershipNumber,
        // Tells the web layer it is embedded, so it renders without its own
        // chrome and enables the JS bridge handshake.
        'embedded': 'true',
        'returnUrl': '$deepLinkScheme://$hostBookingComplete',
        if (sessionToken != null) 'st': sessionToken,
      },
    );
  }

  /// Direct link to a single offer - used by "Continue on web" on a rate card.
  Uri offerUrl({
    required RoomOffer offer,
    required SearchQuery query,
    String? membershipNumber,
    String? sessionToken,
  }) {
    return bookingUrl(
      hotelId: offer.hotelId,
      query: query,
      roomTypeCode: offer.roomType.code,
      ratePlanCode: offer.ratePlanCode,
      membershipNumber: membershipNumber,
      sessionToken: sessionToken,
    );
  }

  /// Property-level "manage my booking" page.
  Uri manageBookingUrl({
    required String confirmationNumber,
    required String lastName,
  }) {
    return Uri.parse('$baseUrl/manage').replace(
      queryParameters: <String, String>{
        'chain': chainId,
        'confirmation': confirmationNumber,
        'lastname': lastName,
        'embedded': 'true',
      },
    );
  }

  /// Turns an intercepted deep link into a typed result.
  static BookingEngineOutcome? parseDeepLink(Uri uri) {
    if (uri.scheme != deepLinkScheme) {
      return null;
    }
    switch (uri.host) {
      case hostBookingComplete:
        return BookingEngineOutcome(
          type: BookingEngineOutcomeType.completed,
          confirmationNumber: uri.queryParameters['confirmation'],
          hotelId: uri.queryParameters['hotel'],
          totalMinor: int.tryParse(uri.queryParameters['totalMinor'] ?? ''),
          currency: uri.queryParameters['currency'],
        );
      case hostBookingCancelled:
        return const BookingEngineOutcome(
          type: BookingEngineOutcomeType.cancelled,
        );
      case hostBookingFailed:
        return BookingEngineOutcome(
          type: BookingEngineOutcomeType.failed,
          message: uri.queryParameters['message'],
        );
      default:
        return null;
    }
  }
}

class BookingEngineOutcome {
  const BookingEngineOutcome({
    required this.type,
    this.confirmationNumber,
    this.hotelId,
    this.totalMinor,
    this.currency,
    this.message,
  });

  final BookingEngineOutcomeType type;
  final String? confirmationNumber;
  final String? hotelId;
  final int? totalMinor;
  final String? currency;
  final String? message;
}

enum BookingEngineOutcomeType { completed, cancelled, failed }
