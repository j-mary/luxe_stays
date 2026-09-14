import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../logging/app_logger.dart';
import 'correlation_interceptor.dart';

/// Exponential backoff with full jitter, for *safe* retries only.
///
/// Two rules keep this from double-booking a guest:
///  1. Only idempotent methods (GET/HEAD) retry automatically.
///  2. A non-idempotent request retries **only** if it carries an
///     `Idempotency-Key` header, which SynXis reservation creation always does
///     (see `SynxisApi.createReservation`).
///
/// Full jitter (`random(0, base * 2^n)`) rather than fixed backoff, so 10k
/// handsets recovering from the same CRS blip do not stampede.
class RetryInterceptor extends Interceptor {
  RetryInterceptor({
    required this._dio,
    required this._logger,
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 300),
    this.maxDelay = const Duration(seconds: 8),
    Random? random,
  }) : _random = random ?? Random();

  static const String _attemptKey = 'retryAttempt';

  final Dio _dio;
  final AppLogger _logger;
  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final Random _random;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final RequestOptions options = err.requestOptions;
    final int attempt = (options.extra[_attemptKey] as int?) ?? 0;

    if (!_shouldRetry(err) || attempt + 1 >= maxAttempts) {
      handler.next(err);
      return;
    }

    final Duration delay = _delayFor(attempt, err);
    _logger.warn(
      'retrying ${options.method} ${options.path} '
      'attempt=${attempt + 2}/$maxAttempts in ${delay.inMilliseconds}ms',
      correlationId: options.extra[CorrelationInterceptor.extraKey] as String?,
    );
    await Future<void>.delayed(delay);

    options.extra[_attemptKey] = attempt + 1;
    try {
      final Response<dynamic> response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  bool _shouldRetry(DioException err) {
    if (err.type == DioExceptionType.cancel) {
      return false;
    }
    if (!_isSafeToReplay(err.requestOptions)) {
      return false;
    }
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final int status = err.response?.statusCode ?? 0;
        return status == 429 || status >= 500;
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
      // A transform timeout is local decoding work, not a transport fault:
      // replaying the request would download and decode the same payload again.
      case DioExceptionType.transformTimeout:
        return false;
    }
  }

  bool _isSafeToReplay(RequestOptions options) {
    final String method = options.method.toUpperCase();
    if (method == 'GET' || method == 'HEAD') {
      return true;
    }
    return options.headers.containsKey('Idempotency-Key');
  }

  /// Honour `Retry-After` when the server sent one; otherwise full jitter.
  Duration _delayFor(int attempt, DioException err) {
    final List<String>? retryAfter = err.response?.headers.map['retry-after'];
    if (retryAfter != null && retryAfter.isNotEmpty) {
      final int? seconds = int.tryParse(retryAfter.first.trim());
      if (seconds != null) {
        return Duration(seconds: seconds.clamp(0, maxDelay.inSeconds).toInt());
      }
    }
    final int ceilingMs = min(
      baseDelay.inMilliseconds * pow(2, attempt).toInt(),
      maxDelay.inMilliseconds,
    );
    return Duration(milliseconds: _random.nextInt(ceilingMs + 1));
  }
}
