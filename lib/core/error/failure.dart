/// Domain-level error taxonomy.
///
/// Transport exceptions (`DioException`, `FormatException`, ...) are mapped
/// into these by [ErrorMapper] so that no layer above `core/network` has to
/// know which HTTP client we use. Each failure carries:
///  * a *user* message  - safe to render, never leaks vendor internals;
///  * a *developer* message and [correlationId] - what we log and what support
///    quotes when raising a ticket with Sabre / Salesforce.
sealed class Failure implements Exception {
  /// [userMessage] is optional-with-default rather than `required` on purpose:
  /// most subclasses supply their own default through a super parameter
  /// (`super.userMessage = '...'`), and a super parameter may only carry a
  /// default when the constructor parameter it forwards to is itself optional.
  const Failure({
    this.userMessage = 'Something went wrong. Please try again.',
    required this.developerMessage,
    this.correlationId,
    this.cause,
  });

  final String userMessage;
  final String developerMessage;
  final String? correlationId;
  final Object? cause;

  /// Whether the caller may safely retry the same request.
  bool get isRetryable => switch (this) {
    NetworkFailure() => true,
    ServerFailure(:final statusCode) => statusCode >= 500,
    RateLimitFailure() => true,
    _ => false,
  };

  @override
  String toString() =>
      '$runtimeType(correlationId: $correlationId, $developerMessage)';
}

/// No usable connection, DNS failure, TLS failure or timeout.
final class NetworkFailure extends Failure {
  const NetworkFailure({
    super.userMessage =
        'We could not reach LuxeStays. Check your connection '
        'and try again.',
    required super.developerMessage,
    super.correlationId,
    super.cause,
  });
}

/// 4xx that is our fault (bad request, validation) or the vendor rejecting the
/// payload. Not retryable without changing the request.
final class ClientFailure extends Failure {
  const ClientFailure({
    required super.userMessage,
    required super.developerMessage,
    required this.statusCode,
    this.vendorCode,
    super.correlationId,
    super.cause,
  });

  final int statusCode;

  /// e.g. SynXis `"HOTEL_NOT_AVAILABLE"`, Salesforce `"INVALID_SESSION_ID"`.
  final String? vendorCode;
}

/// 5xx, or a vendor returning a 200 with a fault body.
final class ServerFailure extends Failure {
  const ServerFailure({
    super.userMessage =
        'Something went wrong on our side. Please try again '
        'in a moment.',
    required super.developerMessage,
    required this.statusCode,
    this.vendorCode,
    super.correlationId,
    super.cause,
  });

  final int statusCode;
  final String? vendorCode;
}

/// 401/403 - token missing, expired beyond refresh, or scope denied.
final class AuthFailure extends Failure {
  const AuthFailure({
    super.userMessage = 'Please sign in again to continue.',
    required super.developerMessage,
    super.correlationId,
    super.cause,
  });
}

/// 429 or a vendor throttling response. Carries the server-suggested wait.
final class RateLimitFailure extends Failure {
  const RateLimitFailure({
    super.userMessage =
        'We are handling a lot of requests right now. '
        'Please try again shortly.',
    required super.developerMessage,
    this.retryAfter,
    super.correlationId,
    super.cause,
  });

  final Duration? retryAfter;
}

/// The response parsed as JSON but did not match the contract we expect.
/// These are the ones worth alerting on: they mean a vendor changed a schema.
final class ContractFailure extends Failure {
  const ContractFailure({
    super.userMessage =
        'We hit an unexpected problem. Our team has been '
        'notified.',
    required super.developerMessage,
    required this.field,
    super.correlationId,
    super.cause,
  });

  final String field;
}

/// Rates/inventory moved between quote and book - the single most common
/// real-world failure in hotel booking. Deserves its own type because the UI
/// response is specific: re-quote and show the new price.
final class RateChangedFailure extends Failure {
  const RateChangedFailure({
    super.userMessage =
        'The price for this room changed while you were '
        'booking. Please review the updated rate.',
    required super.developerMessage,
    required this.previousTotalMinor,
    required this.currentTotalMinor,
    required this.currency,
    super.correlationId,
    super.cause,
  });

  final int previousTotalMinor;
  final int currentTotalMinor;
  final String currency;
}

/// The guest abandoned or the PSP declined the payment.
final class PaymentFailure extends Failure {
  const PaymentFailure({
    required super.userMessage,
    required super.developerMessage,
    required this.reason,
    super.correlationId,
    super.cause,
  });

  final PaymentFailureReason reason;
}

enum PaymentFailureReason { declined, cancelledByUser, timeout, unknown }
