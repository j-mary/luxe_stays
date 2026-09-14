import 'package:dio/dio.dart';

import 'failure.dart';

/// Translates transport-level exceptions into the domain [Failure] taxonomy.
///
/// Each vendor speaks a different error dialect, so the mapper is
/// per-integration: [ErrorMapper.synxis], [ErrorMapper.salesforce], etc. all
/// share the HTTP-status logic but know where *their* vendor hides its error
/// code. Keeping this in one file is deliberate - when Sabre changes a fault
/// envelope there is exactly one place to edit.
class ErrorMapper {
  const ErrorMapper({
    required this.integration,
    required this.vendorCodeReader,
    required this.vendorMessageReader,
  });

  /// Application-owned demo booking error envelope; not a SynXis contract.
  factory ErrorMapper.synxis() => ErrorMapper(
    integration: 'synxis',
    vendorCodeReader: (Object? body) =>
        _firstOf(body, 'Errors', 'Code') ?? _stringAt(body, 'errorCode'),
    vendorMessageReader: (Object? body) =>
        _firstOf(body, 'Errors', 'Message') ?? _stringAt(body, 'message'),
  );

  /// Salesforce REST returns a *list*: `[{"errorCode":"...","message":"..."}]`.
  factory ErrorMapper.salesforce() => ErrorMapper(
    integration: 'salesforce',
    vendorCodeReader: (Object? body) {
      if (body is List && body.isNotEmpty) {
        return _stringAt(body.first, 'errorCode');
      }
      return _stringAt(body, 'errorCode') ?? _stringAt(body, 'error');
    },
    vendorMessageReader: (Object? body) {
      if (body is List && body.isNotEmpty) {
        return _stringAt(body.first, 'message');
      }
      return _stringAt(body, 'message') ?? _stringAt(body, 'error_description');
    },
  );

  /// Contentful returns `{"sys":{"id":"NotFound"},"message":"..."}`.
  factory ErrorMapper.cms() => ErrorMapper(
    integration: 'cms',
    vendorCodeReader: (Object? body) {
      final Object? sys = _at(body, 'sys');
      return _stringAt(sys, 'id');
    },
    vendorMessageReader: (Object? body) => _stringAt(body, 'message'),
  );

  /// The demo Leonardo gateway returns `{"error":"...","code":"..."}`.
  factory ErrorMapper.leonardo() => ErrorMapper(
    integration: 'leonardo',
    vendorCodeReader: (Object? body) => _stringAt(body, 'code'),
    vendorMessageReader: (Object? body) => _stringAt(body, 'error'),
  );

  final String integration;
  final String? Function(Object? body) vendorCodeReader;
  final String? Function(Object? body) vendorMessageReader;

  Failure map(Object error, {String? correlationId}) {
    if (error is Failure) {
      return error;
    }
    if (error is DioException) {
      return _mapDio(error, correlationId: correlationId);
    }
    if (error is FormatException) {
      return ContractFailure(
        developerMessage:
            '[$integration] response was not valid JSON: '
            '${error.message}',
        field: '<root>',
        correlationId: correlationId,
        cause: error,
      );
    }
    return ServerFailure(
      developerMessage: '[$integration] unexpected error: $error',
      statusCode: 0,
      correlationId: correlationId,
      cause: error,
    );
  }

  Failure _mapDio(DioException e, {String? correlationId}) {
    final String? cid =
        correlationId ??
        (e.requestOptions.headers['X-Correlation-Id'] as Object?)?.toString();

    // Exhaustive on purpose - no `default`. When Dio 5.11 added
    // `transformTimeout`, this switch failed to compile and forced a decision
    // about what that case means, instead of silently falling into a default
    // branch and being mapped as an unknown error.
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkFailure(
          developerMessage:
              '[$integration] timeout (${e.type.name}) calling '
              '${e.requestOptions.method} ${e.requestOptions.path}',
          correlationId: cid,
          cause: e,
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
        return NetworkFailure(
          developerMessage:
              '[$integration] transport failure (${e.type.name}): ${e.message}',
          correlationId: cid,
          cause: e,
        );
      case DioExceptionType.cancel:
        return NetworkFailure(
          userMessage: 'Request cancelled.',
          developerMessage: '[$integration] request cancelled by caller',
          correlationId: cid,
          cause: e,
        );
      case DioExceptionType.transformTimeout:
        // Raised when Dio's response transformer (JSON decoding) exceeds its
        // time limit - a local processing problem, not a network one, and
        // usually a symptom of an unexpectedly large payload. Deliberately not
        // a NetworkFailure: replaying the request re-downloads and re-decodes
        // the same body, so it is not retryable.
        return ServerFailure(
          developerMessage:
              '[$integration] response transform timed out for '
              '${e.requestOptions.method} ${e.requestOptions.path} - payload '
              'is likely larger than expected',
          statusCode: 0,
          correlationId: cid,
          cause: e,
        );
      case DioExceptionType.unknown:
        return ServerFailure(
          developerMessage:
              '[$integration] unknown transport error: '
              '${e.message}',
          statusCode: 0,
          correlationId: cid,
          cause: e,
        );
      case DioExceptionType.badResponse:
        return _mapStatus(e, cid);
    }
  }

  Failure _mapStatus(DioException e, String? cid) {
    final Response<dynamic>? response = e.response;
    final int status = response?.statusCode ?? 0;
    final Object? body = response?.data;
    final String? vendorCode = _safe(() => vendorCodeReader(body));
    final String? vendorMessage = _safe(() => vendorMessageReader(body));
    final String dev =
        '[$integration] HTTP $status '
        '${e.requestOptions.method} ${e.requestOptions.path} '
        'vendorCode=$vendorCode vendorMessage=$vendorMessage';

    if (status == 401 || status == 403) {
      return AuthFailure(developerMessage: dev, correlationId: cid, cause: e);
    }
    if (status == 429) {
      return RateLimitFailure(
        developerMessage: dev,
        retryAfter: _retryAfter(response),
        correlationId: cid,
        cause: e,
      );
    }
    if (status >= 500) {
      return ServerFailure(
        developerMessage: dev,
        statusCode: status,
        vendorCode: vendorCode,
        correlationId: cid,
        cause: e,
      );
    }
    // A handful of vendor codes carry booking-specific meaning that the UI
    // must react to differently from a generic 4xx.
    if (vendorCode == 'RATE_CHANGED' || vendorCode == 'PRICE_MISMATCH') {
      final Object? detail = _at(body, 'detail');
      return RateChangedFailure(
        developerMessage: dev,
        previousTotalMinor: _intAt(detail, 'previousTotalMinor') ?? 0,
        currentTotalMinor: _intAt(detail, 'currentTotalMinor') ?? 0,
        currency: _stringAt(detail, 'currency') ?? 'USD',
        correlationId: cid,
        cause: e,
      );
    }
    return ClientFailure(
      userMessage: _userMessageFor(status, vendorCode),
      developerMessage: dev,
      statusCode: status,
      vendorCode: vendorCode,
      correlationId: cid,
      cause: e,
    );
  }

  String _userMessageFor(int status, String? vendorCode) {
    if (status == 404) {
      return 'We could not find what you were looking for.';
    }
    if (status == 409) {
      return 'That room is no longer available. Please pick another option.';
    }
    if (status == 422) {
      return 'Some of the details provided could not be accepted. Please '
          'review and try again.';
    }
    return 'We could not complete that request. Please try again.';
  }

  static Duration? _retryAfter(Response<dynamic>? response) {
    final List<String>? values = response?.headers.map['retry-after'];
    if (values == null || values.isEmpty) {
      return null;
    }
    final int? seconds = int.tryParse(values.first.trim());
    return seconds == null ? null : Duration(seconds: seconds);
  }

  static T? _safe<T>(T? Function() body) {
    try {
      return body();
    } catch (_) {
      return null;
    }
  }

  static Object? _at(Object? body, String key) =>
      body is Map ? body[key] : null;

  static String? _stringAt(Object? body, String key) {
    final Object? value = _at(body, key);
    return value is String ? value : value?.toString();
  }

  static int? _intAt(Object? body, String key) {
    final Object? value = _at(body, key);
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String? _firstOf(Object? body, String listKey, String field) {
    final Object? list = _at(body, listKey);
    if (list is List && list.isNotEmpty) {
      return _stringAt(list.first, field);
    }
    return null;
  }
}
