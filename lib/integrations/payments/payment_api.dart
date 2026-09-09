import '../../core/network/api_client.dart';
import '../../core/result.dart';
import '../../core/utils/money.dart';
import '../../domain/booking.dart';

/// Payment intents, created by our BFF against the PSP.
///
/// The app's entire involvement with money is:
///   1. ask the BFF to create an intent for an amount;
///   2. open the returned hosted page in a WebView;
///   3. receive a result over the bridge and hand the intent id to SynXis.
///
/// It never sees, stores, transmits or processes card data. That is what keeps
/// the mobile app out of PCI-DSS scope (SAQ-A rather than SAQ-A-EP), and it is
/// the single most consequential architectural decision in the payment flow.
/// See `docs/11-SECURITY.md`.
class PaymentApi {
  PaymentApi({required ApiClient client}) : _client = client;

  final ApiClient _client;

  Future<Result<PaymentIntent>> createIntent({
    required Money amount,
    required String cartId,
    required String idempotencyKey,
    required String returnUrl,
    String? membershipNumber,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _client.postJson<PaymentIntent>(
      '/payments/intents',
      idempotencyKey: idempotencyKey,
      body: <String, Object?>{
        'amountMinor': amount.minorUnits,
        'currency': amount.currency,
        'cartId': cartId,
        'returnUrl': returnUrl,
        if (membershipNumber != null) 'membershipNumber': membershipNumber,
        'metadata': metadata,
      },
      decode: (Object? json) {
        final Map<String, Object?> root = JsonRead.object(json, 'root');
        return PaymentIntent(
          intentId: JsonRead.string(root, 'intentId'),
          amount: Money(
            JsonRead.intOf(root, 'amountMinor'),
            JsonRead.stringOrNull(root, 'currency') ?? amount.currency,
          ),
          hostedPageUrl: JsonRead.string(root, 'hostedPageUrl'),
          returnUrl: JsonRead.stringOrNull(root, 'returnUrl') ?? returnUrl,
          expiresAt: JsonRead.dateOrNull(root, 'expiresAt') ??
              DateTime.now().add(const Duration(minutes: 20)),
          provider: JsonRead.stringOrNull(root, 'provider') ?? 'mock-psp',
        );
      },
    );
  }

  /// Server-side truth for an intent.
  ///
  /// The WebView bridge result is a *hint*, not an authority: a hostile or
  /// broken page could post `{"status":"authorized"}` without any money moving.
  /// Before a reservation is created, the status is always confirmed here,
  /// server to server.
  Future<Result<PaymentResult>> verifyIntent(String intentId) {
    return _client.getJson<PaymentResult>(
      '/payments/intents/$intentId',
      decode: (Object? json) {
        final Map<String, Object?> root = JsonRead.object(json, 'root');
        final String status =
            (JsonRead.stringOrNull(root, 'status') ?? '').toLowerCase();
        return PaymentResult(
          intentId: JsonRead.string(root, 'intentId'),
          status: switch (status) {
            'authorized' || 'succeeded' => PaymentStatus.authorized,
            'declined' => PaymentStatus.declined,
            'cancelled' || 'canceled' => PaymentStatus.cancelled,
            'pending' || 'requires_action' => PaymentStatus.pending,
            _ => PaymentStatus.failed,
          },
          authorizationCode: JsonRead.stringOrNull(root, 'authorizationCode'),
          declineReason: JsonRead.stringOrNull(root, 'declineReason'),
          last4: JsonRead.stringOrNull(root, 'last4'),
          brand: JsonRead.stringOrNull(root, 'brand'),
          threeDsPerformed: JsonRead.boolOf(root, 'threeDsPerformed'),
        );
      },
    );
  }
}
