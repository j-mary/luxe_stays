import 'dart:math';

/// Correlation-id / idempotency-key generation.
///
/// Deliberately dependency-free (no `uuid` package) - a v4-shaped id from
/// `Random.secure()` is enough for request tracing, and one fewer transitive
/// dependency in a payment path is a feature.
abstract final class Ids {
  static final Random _random = Random.secure();

  /// RFC-4122 v4 shaped identifier.
  static String uuidV4() {
    final List<int> bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
    final String hex =
        bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  /// Short, log-friendly correlation id (`ls_` prefix = LuxeStays).
  static String correlationId() =>
      'ls_${DateTime.now().toUtc().millisecondsSinceEpoch.toRadixString(36)}_'
      '${uuidV4().substring(0, 8)}';

  /// Idempotency key for reservation creation. Derived from the cart so a
  /// retry after a timeout can never double-book a guest.
  static String idempotencyKeyFor(String cartId, int revision) =>
      'book_${cartId}_r$revision';
}
