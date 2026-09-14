import 'package:flutter_test/flutter_test.dart';
import 'package:luxe_stays/core/logging/app_logger.dart';

void main() {
  group('AppLogger.redact', () {
    test('masks credentials and card data at any depth', () {
      final Map<String, Object?> redacted = AppLogger.redact(<String, Object?>{
        'Authorization': 'Bearer secret-token',
        'guest': <String, Object?>{
          'email': 'guest@example.com',
          'firstName': 'Amara',
          'loyaltyId': 'LS-100042',
        },
        'payment': <String, Object?>{
          'cardNumber': '4242424242424242',
          'cvv': '123',
          'amountMinor': 45000,
        },
      });

      expect(redacted['Authorization'], '***');
      final Map<String, Object?> guest =
          redacted['guest']! as Map<String, Object?>;
      expect(guest['email'], '***');
      expect(guest['firstName'], '***');
      // Non-sensitive fields must survive, or the logs stop being useful.
      expect(guest['loyaltyId'], 'LS-100042');

      final Map<String, Object?> payment =
          redacted['payment']! as Map<String, Object?>;
      expect(payment['cardNumber'], '***');
      expect(payment['cvv'], '***');
      expect(payment['amountMinor'], 45000);
    });

    test('redacts inside lists of maps', () {
      final Map<String, Object?> redacted = AppLogger.redact(<String, Object?>{
        'guests': <Object?>[
          <String, Object?>{'email': 'a@example.com', 'nights': 2},
          <String, Object?>{'email': 'b@example.com', 'nights': 3},
        ],
      });
      final List<Object?> guests = redacted['guests']! as List<Object?>;
      for (final Object? guest in guests) {
        expect((guest! as Map<String, Object?>)['email'], '***');
      }
    });

    test('is case-insensitive about key names', () {
      expect(
        AppLogger.redact(<String, Object?>{
          'ACCESS_TOKEN': 'x',
        })['ACCESS_TOKEN'],
        '***',
      );
    });
  });
}
