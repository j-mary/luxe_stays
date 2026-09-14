import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luxe_stays/webview/bridge/webview_bridge.dart';

import '../app/providers.dart';
import '../domain/search.dart';
import '../integrations/synxis/synxis_booking_engine.dart';
import 'bridge/bridge_message.dart';
import 'hybrid_webview.dart';

/// The SynXis Booking Engine, embedded.
///
/// This is the "web where we must comply" half of the hybrid split. The native
/// app owns discovery - search, filtering, comparison, the cart, loyalty - and
/// hands off to the CRS's own web flow for the parts Sabre configures per
/// property and per region: packages and add-ons, tax and fee disclosures,
/// consent text, and any market-specific booking rules.
///
/// The payoff is operational: a property adds a spa package in SynXis on a
/// Tuesday and it is bookable in the app on Tuesday, with no release, no store
/// review and no re-certification.
///
/// The cost is that the screen is only as good as the contract in
/// `docs/02-WEBVIEW-BRIDGE.md` - which is why that contract is versioned,
/// origin-checked and tested.
class BookingEngineWebViewScreen extends ConsumerWidget {
  const BookingEngineWebViewScreen({
    required this.hotelId,
    required this.hotelName,
    required this.query,
    this.roomTypeCode,
    this.ratePlanCode,
    this.membershipNumber,
    super.key,
  });

  final String hotelId;
  final String hotelName;
  final SearchQuery query;
  final String? roomTypeCode;
  final String? ratePlanCode;
  final String? membershipNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SynxisBookingEngine engine = ref.watch(bookingEngineProvider);
    final Uri uri = engine.bookingUrl(
      hotelId: hotelId,
      query: query,
      roomTypeCode: roomTypeCode,
      ratePlanCode: ratePlanCode,
      membershipNumber: membershipNumber,
    );

    void finish(BookingEngineOutcome outcome) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(outcome);
      }
    }

    return HybridWebView(
      initialUri: uri,
      title: hotelName,
      confirmOnExit: true,
      exitConfirmationText:
          'Your booking is not finished. Leave the booking page?',
      handlers: <BridgeMessageType, BridgeHandler>{
        BridgeMessageType.bookingResult: (BridgeMessage message) {
          final String status = (message.stringField('status') ?? '')
              .toLowerCase();
          finish(
            BookingEngineOutcome(
              type: switch (status) {
                'completed' ||
                'confirmed' => BookingEngineOutcomeType.completed,
                'cancelled' || 'canceled' => BookingEngineOutcomeType.cancelled,
                _ => BookingEngineOutcomeType.failed,
              },
              confirmationNumber: message.stringField('confirmationNumber'),
              hotelId: hotelId,
              totalMinor: message.intField('totalMinor'),
              currency: message.stringField('currency'),
              message: message.stringField('message'),
            ),
          );
        },
      },
      onDeepLink: (Uri deepLink) {
        final BookingEngineOutcome? outcome = SynxisBookingEngine.parseDeepLink(
          deepLink,
        );
        if (outcome == null) {
          return false;
        }
        finish(outcome);
        return true;
      },
    );
  }
}
