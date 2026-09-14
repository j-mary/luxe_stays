import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luxe_stays/core/error/error_mapper.dart';
import 'package:luxe_stays/core/error/failure.dart';

DioException _badResponse({
  required int status,
  Object? body,
  Map<String, List<String>> headers = const <String, List<String>>{},
}) {
  final RequestOptions options = RequestOptions(path: '/v1/api/availability');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: options,
      statusCode: status,
      data: body,
      headers: Headers.fromMap(headers),
    ),
  );
}

void main() {
  group('ErrorMapper.synxis', () {
    final ErrorMapper mapper = ErrorMapper.synxis();

    test('reads the SynXis Errors envelope', () {
      final Failure failure = mapper.map(
        _badResponse(
          status: 409,
          body: <String, Object?>{
            'Errors': <Object?>[
              <String, Object?>{
                'Code': 'HOTEL_NOT_AVAILABLE',
                'Message': 'No inventory',
              },
            ],
          },
        ),
      );
      expect(failure, isA<ClientFailure>());
      expect((failure as ClientFailure).vendorCode, 'HOTEL_NOT_AVAILABLE');
      expect(failure.isRetryable, isFalse);
      // The guest sees actionable copy, never the vendor code.
      expect(failure.userMessage, contains('no longer available'));
    });

    test('promotes a rate change to its own failure type', () {
      final Failure failure = mapper.map(
        _badResponse(
          status: 409,
          body: <String, Object?>{
            'Errors': <Object?>[
              <String, Object?>{'Code': 'RATE_CHANGED', 'Message': 'moved'},
            ],
            'detail': <String, Object?>{
              'previousTotalMinor': 120000,
              'currentTotalMinor': 131000,
              'currency': 'EUR',
            },
          },
        ),
      );
      expect(failure, isA<RateChangedFailure>());
      final RateChangedFailure rate = failure as RateChangedFailure;
      expect(rate.previousTotalMinor, 120000);
      expect(rate.currentTotalMinor, 131000);
      expect(rate.currency, 'EUR');
    });

    test('5xx is retryable, 4xx is not', () {
      expect(mapper.map(_badResponse(status: 503)).isRetryable, isTrue);
      expect(mapper.map(_badResponse(status: 422)).isRetryable, isFalse);
    });

    test('429 carries the server-supplied Retry-After', () {
      final Failure failure = mapper.map(
        _badResponse(
          status: 429,
          headers: const <String, List<String>>{
            'retry-after': <String>['12'],
          },
        ),
      );
      expect(failure, isA<RateLimitFailure>());
      expect(
        (failure as RateLimitFailure).retryAfter,
        const Duration(seconds: 12),
      );
    });

    test('timeouts become NetworkFailure', () {
      final Failure failure = mapper.map(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.receiveTimeout,
        ),
      );
      expect(failure, isA<NetworkFailure>());
      expect(failure.isRetryable, isTrue);
    });
  });

  group('ErrorMapper.salesforce', () {
    final ErrorMapper mapper = ErrorMapper.salesforce();

    test('reads the array-shaped Salesforce error body', () {
      final Failure failure = mapper.map(
        _badResponse(
          status: 400,
          body: <Object?>[
            <String, Object?>{
              'errorCode': 'INSUFFICIENT_POINTS',
              'message': 'Not enough points',
            },
          ],
        ),
      );
      expect(failure, isA<ClientFailure>());
      expect((failure as ClientFailure).vendorCode, 'INSUFFICIENT_POINTS');
    });

    test('401 becomes AuthFailure so the session can be renewed', () {
      expect(
        mapper.map(_badResponse(status: 401, body: <Object?>[])),
        isA<AuthFailure>(),
      );
    });
  });

  group('ErrorMapper.cms', () {
    test('reads the Contentful sys.id error code', () {
      final Failure failure = ErrorMapper.cms().map(
        _badResponse(
          status: 404,
          body: <String, Object?>{
            'sys': <String, Object?>{'id': 'NotFound'},
            'message': 'The resource could not be found.',
          },
        ),
      );
      expect((failure as ClientFailure).vendorCode, 'NotFound');
    });
  });
}
