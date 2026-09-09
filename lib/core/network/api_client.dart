import 'package:dio/dio.dart';

import '../analytics/analytics.dart';
import '../config/app_config.dart';
import '../error/error_mapper.dart';
import '../error/failure.dart';
import '../logging/app_logger.dart';
import '../result.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/correlation_interceptor.dart';
import 'interceptors/logging_interceptor.dart';
import 'interceptors/retry_interceptor.dart';

/// One [ApiClient] per integration.
///
/// Each vendor gets its own Dio instance because they disagree about
/// everything that matters: base URL, auth scheme, timeouts, error envelope,
/// how aggressively you may retry. Sharing one client would mean the Leonardo
/// CDN's generous timeouts govern SynXis booking calls, which is exactly how
/// you end up holding a reservation open for 60s.
///
/// The client exposes a narrow surface - [getJson], [postJson] and friends -
/// that returns [Result] rather than throwing, with vendor errors already
/// translated by an [ErrorMapper].
class ApiClient {
  ApiClient({
    required Dio dio,
    required ErrorMapper errorMapper,
    required AppLogger logger,
  })  : _dio = dio,
        _errorMapper = errorMapper,
        _logger = logger;

  /// Builds a configured client. [authInterceptor] is optional: the CMS and
  /// Leonardo read paths use a delivery token pinned in [headers] instead.
  factory ApiClient.build({
    required String baseUrl,
    required String integration,
    required AppConfig config,
    required AppLogger logger,
    ErrorMapper? errorMapper,
    Map<String, String> headers = const <String, String>{},
    AuthInterceptor? authInterceptor,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration receiveTimeout = const Duration(seconds: 20),
    int maxRetryAttempts = 3,
    HttpClientAdapter? adapter,
  }) {
    final Dio dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        sendTimeout: connectTimeout,
        responseType: ResponseType.json,
        headers: <String, String>{
          'Accept': 'application/json',
          'X-Client': 'luxestays-mobile',
          ...headers,
        },
        // We map non-2xx ourselves, but let Dio raise so the error pipeline
        // (retry → auth refresh → mapper) is the single path for failures.
        validateStatus: (int? status) => status != null && status < 400,
      ),
    );
    if (adapter != null) {
      dio.httpClientAdapter = adapter;
    }

    dio.interceptors.add(CorrelationInterceptor());
    if (authInterceptor != null) {
      dio.interceptors.add(authInterceptor);
    }
    dio.interceptors.add(
      RetryInterceptor(dio: dio, logger: logger, maxAttempts: maxRetryAttempts),
    );
    dio.interceptors.add(
      LoggingInterceptor(
        logger: logger,
        integration: integration,
        verbose: config.verboseNetworkLogging,
      ),
    );

    return ApiClient(
      dio: dio,
      errorMapper: errorMapper ??
          ErrorMapper(
            integration: integration,
            vendorCodeReader: (Object? body) => null,
            vendorMessageReader: (Object? body) => null,
          ),
      logger: logger,
    );
  }

  final Dio _dio;
  final ErrorMapper _errorMapper;
  final AppLogger _logger;

  /// Exposed for tests, which swap in `DioAdapter`/a fake adapter.
  Dio get raw => _dio;

  Future<Result<T>> getJson<T>(
    String path, {
    Map<String, Object?>? query,
    Map<String, String>? headers,
    required T Function(Object? json) decode,
    CancelToken? cancelToken,
  }) {
    return _send<T>(
      () => _dio.get<dynamic>(
        path,
        queryParameters: query,
        options: Options(headers: headers),
        cancelToken: cancelToken,
      ),
      decode,
    );
  }

  Future<Result<T>> postJson<T>(
    String path, {
    Object? body,
    Map<String, Object?>? query,
    Map<String, String>? headers,
    String? idempotencyKey,
    required T Function(Object? json) decode,
    CancelToken? cancelToken,
  }) {
    return _send<T>(
      () => _dio.post<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(
          headers: <String, String>{
            if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
            ...?headers,
          },
        ),
        cancelToken: cancelToken,
      ),
      decode,
    );
  }

  Future<Result<T>> patchJson<T>(
    String path, {
    Object? body,
    Map<String, String>? headers,
    required T Function(Object? json) decode,
    CancelToken? cancelToken,
  }) {
    return _send<T>(
      () => _dio.patch<dynamic>(
        path,
        data: body,
        options: Options(headers: headers),
        cancelToken: cancelToken,
      ),
      decode,
    );
  }

  Future<Result<T>> deleteJson<T>(
    String path, {
    Map<String, Object?>? query,
    required T Function(Object? json) decode,
    CancelToken? cancelToken,
  }) {
    return _send<T>(
      () => _dio.delete<dynamic>(
        path,
        queryParameters: query,
        cancelToken: cancelToken,
      ),
      decode,
    );
  }

  Future<Result<T>> _send<T>(
    Future<Response<dynamic>> Function() request,
    T Function(Object? json) decode,
  ) async {
    try {
      final Response<dynamic> response = await request();
      try {
        return Ok<T>(decode(response.data));
      } on Failure catch (f) {
        logFailure(f);
        return Err<T>(f);
      } catch (e, s) {
        // A decode blow-up is a *contract* problem, not a network problem: the
        // vendor changed a schema. Surfacing it as its own failure type is what
        // lets us alert on it separately.
        final Failure failure = ContractFailure(
          developerMessage: 'failed to decode ${response.requestOptions.path}: '
              '$e',
          field: '<unknown>',
          correlationId: response
              .requestOptions.extra[CorrelationInterceptor.extraKey] as String?,
          cause: e,
        );
        _logger.error(
          failure.developerMessage,
          correlationId: failure.correlationId,
          error: e,
          stackTrace: s,
        );
        return Err<T>(failure);
      }
    } catch (e) {
      final Failure failure = _errorMapper.map(e);
      return Err<T>(failure);
    }
  }

  void logFailure(Failure failure) {
    _logger.warn(failure.developerMessage,
        correlationId: failure.correlationId);
  }

  void close() => _dio.close(force: true);
}

/// Small helpers used by every mapper. They exist so that a missing or
/// wrong-typed field produces a [ContractFailure] naming the field, instead of
/// a bare `type 'Null' is not a subtype of 'String'` in a crash report.
abstract final class JsonRead {
  static Map<String, Object?> object(Object? json, String field) {
    if (json is Map<String, Object?>) {
      return json;
    }
    if (json is Map) {
      return json.map(
        (Object? k, Object? v) => MapEntry<String, Object?>(k.toString(), v),
      );
    }
    throw ContractFailure(
      developerMessage: 'expected object at "$field", got ${json.runtimeType}',
      field: field,
    );
  }

  static List<Object?> list(Object? json, String field) {
    if (json is List) {
      return json;
    }
    throw ContractFailure(
      developerMessage: 'expected array at "$field", got ${json.runtimeType}',
      field: field,
    );
  }

  static String string(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    if (value is String) {
      return value;
    }
    if (value != null) {
      return value.toString();
    }
    throw ContractFailure(
      developerMessage: 'missing required string "$field" in $json',
      field: field,
    );
  }

  static String? stringOrNull(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    return value is String ? value : value?.toString();
  }

  static int intOf(Map<String, Object?> json, String field, {int? fallback}) {
    final Object? value = json[field];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final int? parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    if (fallback != null) return fallback;
    throw ContractFailure(
      developerMessage: 'missing required int "$field" in $json',
      field: field,
    );
  }

  static double? doubleOrNull(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static bool boolOf(Map<String, Object?> json, String field,
      {bool fallback = false}) {
    final Object? value = json[field];
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return fallback;
  }

  static DateTime dateOf(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    if (value is String) {
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw ContractFailure(
      developerMessage: 'missing/invalid date "$field" in $json',
      field: field,
    );
  }

  static DateTime? dateOrNull(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    return value is String ? DateTime.tryParse(value) : null;
  }

  static List<Map<String, Object?>> objectList(Object? json, String field) {
    return list(json, field)
        .map((Object? e) => object(e, '$field[]'))
        .toList(growable: false);
  }
}

/// Convenience so `AnalyticsService` errors can be reported from any client.
extension AnalyticsFailureX on AnalyticsService {
  void reportFailure(Failure failure) {
    event('api_failure', parameters: <String, Object?>{
      'type': failure.runtimeType.toString(),
      'correlation_id': failure.correlationId,
    });
  }
}
