import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luxe_stays/core/config/app_config.dart';
import 'package:luxe_stays/core/error/failure.dart';
import 'package:luxe_stays/core/logging/app_logger.dart';
import 'package:luxe_stays/core/network/api_client.dart';

class FailingTransport implements HttpClientAdapter {
  FailingTransport(this.type);
  final DioExceptionType type;
  int attempts = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    attempts++;
    throw DioException(requestOptions: options, type: type);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  for (final DioExceptionType type in [
    DioExceptionType.connectionError,
    DioExceptionType.receiveTimeout,
  ]) {
    test('$type becomes a recoverable failure with bounded retries', () async {
      final FailingTransport transport = FailingTransport(type);
      final ApiClient client = ApiClient.build(
        baseUrl: 'http://localhost',
        integration: 'demo',
        config: AppConfig.fromEnvironment(),
        logger: AppLogger(sinks: []),
        adapter: transport,
        maxRetryAttempts: 2,
      );
      addTearDown(client.close);
      final result = await client.getJson<Object?>(
        '/hotels',
        decode: (Object? value) => value,
      );
      expect(result.failureOrNull, isA<NetworkFailure>());
      expect(transport.attempts, 2);
    });
  }
  test(
    'a timed-out POST without a replay guarantee is never retried',
    () async {
      final FailingTransport transport = FailingTransport(
        DioExceptionType.receiveTimeout,
      );
      final ApiClient client = ApiClient.build(
        baseUrl: 'http://localhost',
        integration: 'demo',
        config: AppConfig.fromEnvironment(),
        logger: AppLogger(sinks: []),
        adapter: transport,
      );
      addTearDown(client.close);
      await client.postJson<Object?>(
        '/reservations',
        decode: (Object? value) => value,
      );
      expect(transport.attempts, 1);
    },
  );
}
