import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luxe_stays/webview/bridge/webview_bridge.dart';

import '../app/providers.dart';
import '../core/analytics/analytics.dart';
import '../domain/booking.dart';
import 'bridge/bridge_message.dart';
import 'hybrid_webview.dart';

/// The hosted payment page, in a WebView.
///
/// ### Why a WebView here specifically
/// Because the card fields must never be Flutter widgets. If the app rendered
/// the PAN input, the handset would be in PCI-DSS scope (SAQ-A-EP or worse) and
/// every release would need re-assessment. Rendering the PSP's own hosted page
/// keeps us at SAQ-A: card data goes from the guest's keyboard to the PSP's
/// origin and never touches our process.
///
/// It also gets 3-D Secure / SCA for free. Issuer step-up is a redirect-driven
/// dance with the bank's own page; a native card form would have to re-host all
/// of it.
///
/// ### The result path
/// Two signals arrive, and both are treated as *hints*:
///  1. a bridge message ([BridgeMessageType.paymentResult]), and/or
///  2. a `luxestays://payment-*` deep link, for PSPs that only redirect.
///
/// Whichever arrives first pops the screen with a [PaymentResult]. The caller
/// then re-verifies server-side before creating a reservation - see
/// `BookingRepository.complete`.
class PaymentWebViewScreen extends ConsumerStatefulWidget {
  const PaymentWebViewScreen({required this.intent, super.key});

  final PaymentIntent intent;

  static const String hostSuccess = 'payment-success';
  static const String hostFailure = 'payment-failure';
  static const String hostCancel = 'payment-cancel';

  @override
  ConsumerState<PaymentWebViewScreen> createState() =>
      _PaymentWebViewScreenState();
}

class _PaymentWebViewScreenState extends ConsumerState<PaymentWebViewScreen> {
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).event(
      AnalyticsEvents.paymentWebviewOpened,
      parameters: <String, Object?>{
        'intent_id': widget.intent.intentId,
        'provider': widget.intent.provider,
        'amount_minor': widget.intent.amount.minorUnits,
      },
    );
  }

  /// Guards against a double pop: a PSP that both posts a bridge message and
  /// redirects would otherwise pop twice and tear down the route below.
  void _finish(PaymentResult result) {
    if (_completed || !mounted) {
      return;
    }
    _completed = true;
    ref.read(analyticsProvider).event(
      AnalyticsEvents.paymentWebviewResult,
      parameters: <String, Object?>{
        'intent_id': result.intentId,
        'status': result.status.name,
        'three_ds': result.threeDsPerformed,
      },
    );
    Navigator.of(context).pop(result);
  }

  bool _onDeepLink(Uri uri) {
    switch (uri.host) {
      case PaymentWebViewScreen.hostSuccess:
        _finish(
          PaymentResult(
            intentId: uri.queryParameters['intent'] ?? widget.intent.intentId,
            status: PaymentStatus.authorized,
            authorizationCode: uri.queryParameters['auth'],
            last4: uri.queryParameters['last4'],
            brand: uri.queryParameters['brand'],
            threeDsPerformed: uri.queryParameters['threeds'] == 'true',
          ),
        );
        return true;
      case PaymentWebViewScreen.hostFailure:
        _finish(
          PaymentResult(
            intentId: widget.intent.intentId,
            status: PaymentStatus.declined,
            declineReason: uri.queryParameters['reason'],
          ),
        );
        return true;
      case PaymentWebViewScreen.hostCancel:
        _finish(
          PaymentResult(
            intentId: widget.intent.intentId,
            status: PaymentStatus.cancelled,
          ),
        );
        return true;
      default:
        return false;
    }
  }

  void _onBridgeResult(BridgeMessage message) {
    final String status = (message.stringField('status') ?? '').toLowerCase();
    _finish(
      PaymentResult(
        intentId: message.stringField('intentId') ?? widget.intent.intentId,
        status: switch (status) {
          'authorized' || 'succeeded' => PaymentStatus.authorized,
          'declined' => PaymentStatus.declined,
          'cancelled' || 'canceled' => PaymentStatus.cancelled,
          'pending' => PaymentStatus.pending,
          _ => PaymentStatus.failed,
        },
        authorizationCode: message.stringField('authorizationCode'),
        declineReason: message.stringField('declineReason'),
        last4: message.stringField('last4'),
        brand: message.stringField('brand'),
        threeDsPerformed: message.boolField('threeDsPerformed'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return HybridWebView(
      initialUri: Uri.parse(widget.intent.hostedPageUrl),
      title: 'Secure payment',
      confirmOnExit: true,
      exitConfirmationText:
          'Your payment has not been completed. Leave this page?',
      handlers: <BridgeMessageType, BridgeHandler>{
        BridgeMessageType.paymentResult: _onBridgeResult,
      },
      onDeepLink: _onDeepLink,
      onLoadError: (String description) {
        _finish(
          PaymentResult(
            intentId: widget.intent.intentId,
            status: PaymentStatus.failed,
            declineReason: 'The payment page could not be loaded.',
          ),
        );
      },
    );
  }
}
