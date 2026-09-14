import 'package:dio/dio.dart';

import '../../logging/app_logger.dart';
import 'correlation_interceptor.dart';

/// Redaction-aware HTTP logging.
///
/// * Headers and bodies pass through [AppLogger.redact] - a bearer token or a
///   card PAN can never reach logcat/Console.
/// * Bodies are only logged when [verbose] (dev/staging), and are truncated.
/// * Every line carries the correlation id and the wall-clock duration, which
///   is what you actually need when chasing "the search screen feels slow".
class LoggingInterceptor extends Interceptor {
  LoggingInterceptor({
    required this._logger,
    required this.integration,
    this.verbose = false,
    this.maxBodyChars = 2000,
  });

  final AppLogger _logger;
  final String integration;
  final bool verbose;
  final int maxBodyChars;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _logger.debug(
      '→ ${options.method} ${options.uri}',
      correlationId: options.extra[CorrelationInterceptor.extraKey] as String?,
      context: <String, Object?>{
        'integration': integration,
        'headers': AppLogger.redact(options.headers),
        if (verbose && options.data != null) 'body': _truncate(options.data),
      },
    );
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _logger.info(
      '← ${response.statusCode} ${response.requestOptions.method} '
      '${response.requestOptions.uri}',
      correlationId:
          response.requestOptions.extra[CorrelationInterceptor.extraKey]
              as String?,
      context: <String, Object?>{
        'integration': integration,
        'durationMs': _durationMs(response.requestOptions),
        if (verbose) 'body': _truncate(response.data),
      },
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _logger.warn(
      '✗ ${err.response?.statusCode ?? err.type.name} '
      '${err.requestOptions.method} ${err.requestOptions.uri}',
      correlationId:
          err.requestOptions.extra[CorrelationInterceptor.extraKey] as String?,
      context: <String, Object?>{
        'integration': integration,
        'durationMs': _durationMs(err.requestOptions),
        'body': _truncate(err.response?.data),
      },
      error: err.message,
    );
    handler.next(err);
  }

  int? _durationMs(RequestOptions options) {
    final Object? startedAt = options.extra['startedAtMs'];
    if (startedAt is! int) {
      return null;
    }
    return DateTime.now().millisecondsSinceEpoch - startedAt;
  }

  Object? _truncate(Object? body) {
    if (body == null) {
      return null;
    }
    final Object safe = body is Map ? AppLogger.redact(body) : body;
    final String text = safe.toString();
    return text.length <= maxBodyChars
        ? text
        : '${text.substring(0, maxBodyChars)}…(${text.length} chars)';
  }
}
