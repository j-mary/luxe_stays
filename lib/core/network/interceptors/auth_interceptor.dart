import 'dart:async';

import 'package:dio/dio.dart';

import '../../logging/app_logger.dart';
import '../../storage/token_store.dart';
import 'correlation_interceptor.dart';

/// Signature of "get me a valid token, refreshing if you must".
typedef TokenRefresher = Future<OAuthTokens?> Function();

/// Attaches the bearer token and performs single-flight refresh on 401.
///
/// It extends [QueuedInterceptor] (not [Interceptor]) on purpose: Dio processes
/// queued interceptors one request at a time, so ten parallel calls that all
/// hit an expired token trigger **one** refresh, not ten. Without this you get
/// the classic refresh-token stampede that invalidates its own rotation.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this._store,
    required this._tokenKey,
    required this._refresher,
    required this._logger,
    this.onAuthenticationLost,
  });

  /// Requests marked with this extra skip the interceptor entirely - used by
  /// the token endpoint itself, otherwise refresh would recurse forever.
  static const String skipAuthExtra = 'skipAuth';
  static const String _retriedExtra = 'authRetried';

  final TokenStore _store;
  final String _tokenKey;
  final TokenRefresher _refresher;
  final AppLogger _logger;
  final void Function()? onAuthenticationLost;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[skipAuthExtra] == true) {
      handler.next(options);
      return;
    }

    OAuthTokens? tokens = await _store.read(_tokenKey);
    if (tokens == null || tokens.isExpired) {
      tokens = await _refreshSafely(options);
    }
    if (tokens != null) {
      options.headers['Authorization'] = tokens.authorizationHeader;
      // Salesforce hands back the org's instance URL with the token; requests
      // must go there rather than to login.salesforce.com.
      final String? instanceUrl = tokens.instanceUrl;
      if (instanceUrl != null && instanceUrl.isNotEmpty) {
        options.extra['instanceUrl'] = instanceUrl;
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final RequestOptions options = err.requestOptions;
    final int? status = err.response?.statusCode;
    final bool alreadyRetried = options.extra[_retriedExtra] == true;

    if (status != 401 ||
        alreadyRetried ||
        options.extra[skipAuthExtra] == true) {
      handler.next(err);
      return;
    }

    _logger.warn(
      '401 - refreshing credentials once and replaying '
      '${options.method} ${options.path}',
      correlationId: options.extra[CorrelationInterceptor.extraKey] as String?,
    );

    final OAuthTokens? tokens = await _refreshSafely(options);
    if (tokens == null) {
      await _store.delete(_tokenKey);
      onAuthenticationLost?.call();
      handler.next(err);
      return;
    }

    options.extra[_retriedExtra] = true;
    options.headers['Authorization'] = tokens.authorizationHeader;
    try {
      final Dio dio = Dio(BaseOptions(baseUrl: options.baseUrl));
      final Response<dynamic> response = await dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<OAuthTokens?> _refreshSafely(RequestOptions options) async {
    try {
      final OAuthTokens? tokens = await _refresher();
      if (tokens != null) {
        await _store.write(_tokenKey, tokens);
      }
      return tokens;
    } catch (e, s) {
      _logger.error(
        'token refresh failed',
        correlationId:
            options.extra[CorrelationInterceptor.extraKey] as String?,
        error: e,
        stackTrace: s,
      );
      return null;
    }
  }
}
