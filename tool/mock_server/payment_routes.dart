import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'support.dart';
import 'web_pages.dart';

/// Mock **payment service provider** plus the BFF endpoints in front of it.
///
/// The split mirrors production: the app asks *our* server to create an intent,
/// our server talks to the PSP, and the app only ever receives an intent id and
/// a URL to open. The hosted page itself is served from `/pay`.
Router paymentRouter() {
  final Router router = Router();

  router.post('/intents', (Request request) async {
    final String? key = request.headers['idempotency-key'];
    final Object? replay = idempotency.get(key);
    if (replay != null) {
      return jsonResponse(replay,
          headers: <String, String>{'x-idempotent-replay': '1'});
    }

    final Map<String, Object?> body = await readJson(request);
    final int amount = (body['amountMinor'] as num?)?.toInt() ?? 0;
    final String currency = (body['currency'] as String?) ?? 'USD';
    final String intentId = 'pi_${DateTime.now().millisecondsSinceEpoch}';

    paymentIntents[intentId] = MockIntent(
      id: intentId,
      amountMinor: amount,
      currency: currency,
      cartId: (body['cartId'] as String?) ?? '',
    );

    final Map<String, Object?> payload = <String, Object?>{
      'intentId': intentId,
      'amountMinor': amount,
      'currency': currency,
      'provider': 'mock-psp',
      'hostedPageUrl': 'http://localhost:8080/pay?intent=$intentId',
      'returnUrl':
          (body['returnUrl'] as String?) ?? 'luxestays://payment-success',
      'expiresAt':
          DateTime.now().add(const Duration(minutes: 20)).toIso8601String(),
    };
    idempotency.put(key, payload);
    return jsonResponse(payload, status: 201);
  });

  /// Server-side verification. This is the authority - the bridge message from
  /// the WebView is only ever a hint.
  router.get('/intents/<intentId>', (Request request, String intentId) {
    final MockIntent? intent = paymentIntents[intentId];
    if (intent == null) {
      return jsonResponse(
        <String, Object?>{'error': 'Unknown intent', 'code': 'NOT_FOUND'},
        status: 404,
      );
    }
    return jsonResponse(<String, Object?>{
      'intentId': intent.id,
      'status': intent.status,
      'amountMinor': intent.amountMinor,
      'currency': intent.currency,
      'authorizationCode': intent.authorizationCode,
      'declineReason': intent.declineReason,
      'last4': intent.last4,
      'brand': intent.brand,
      'threeDsPerformed': intent.threeDsPerformed,
    });
  });

  /// Called by the hosted page when the guest submits.
  router.post('/intents/<intentId>/authorize',
      (Request request, String intentId) async {
    final MockIntent? intent = paymentIntents[intentId];
    if (intent == null) {
      return jsonResponse(<String, Object?>{'error': 'Unknown intent'},
          status: 404);
    }
    final Map<String, Object?> body = await readJson(request);
    final String outcome = (body['outcome'] as String?) ?? 'authorize';

    switch (outcome) {
      case 'decline':
        intent.status = 'declined';
        intent.declineReason = 'Your bank declined this payment (51).';
        break;
      case 'cancel':
        intent.status = 'cancelled';
        break;
      default:
        intent.status = 'authorized';
        intent.authorizationCode = reference('AUTH');
        intent.last4 = '4242';
        intent.brand = 'visa';
        intent.threeDsPerformed = body['threeDs'] == true;
    }

    return jsonResponse(<String, Object?>{
      'intentId': intent.id,
      'status': intent.status,
      'authorizationCode': intent.authorizationCode,
      'declineReason': intent.declineReason,
      'last4': intent.last4,
      'brand': intent.brand,
      'threeDsPerformed': intent.threeDsPerformed,
    });
  });

  return router;
}

class MockIntent {
  MockIntent({
    required this.id,
    required this.amountMinor,
    required this.currency,
    required this.cartId,
  });

  final String id;
  final int amountMinor;
  final String currency;
  final String cartId;

  String status = 'requires_payment_method';
  String? authorizationCode;
  String? declineReason;
  String? last4;
  String? brand;
  bool threeDsPerformed = false;
}

final Map<String, MockIntent> paymentIntents = <String, MockIntent>{};

/// The hosted payment page itself.
Handler hostedPaymentHandler() {
  return (Request request) {
    final String intentId = request.url.queryParameters['intent'] ?? '';
    final MockIntent? intent = paymentIntents[intentId];
    return html(
      hostedPaymentPage(
        intentId: intentId,
        amountMinor: intent?.amountMinor ?? 0,
        currency: intent?.currency ?? 'USD',
      ),
    );
  };
}
