import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../core/logging/app_logger.dart';
import '../../core/storage/token_store.dart';

/// Salesforce authentication.
///
/// ### Which OAuth flow, and why
///
/// Salesforce offers several. For a *public mobile client* only one is
/// defensible: **Authorization Code with PKCE** (RFC 7636). A mobile binary
/// cannot keep a client secret, so the JWT bearer and username-password flows
/// are off the table, and the implicit flow leaks tokens through the redirect.
///
/// This POC therefore does two things:
///  1. [buildAuthorizationUrl] / [exchangeCode] implement PKCE against the
///     Salesforce `/services/oauth2/authorize` + `/token` endpoints. The
///     authorize page is rendered **in a WebView** - which is the one place a
///     WebView is genuinely load-bearing for auth in this app.
///  2. [refresh] rotates the token, single-flighted by `AuthInterceptor`.
///
/// In production the safer variant - and the one recommended here - is for the
/// handset to authenticate against our own BFF, and for the BFF to hold the
/// Salesforce connected-app credentials server side. The client code is
/// identical; only [tokenEndpoint] changes. See `docs/04-INTEGRATION-SALESFORCE.md`.
class SalesforceAuthService {
  SalesforceAuthService({
    required Dio dio,
    required TokenStore store,
    required AppLogger logger,
    required this.clientId,
    required this.redirectUri,
    required this.loginBaseUrl,
    this.scopes = const <String>['api', 'refresh_token', 'openid'],
  })  : _dio = dio,
        _store = store,
        _logger = logger;

  final Dio _dio;
  final TokenStore _store;
  final AppLogger _logger;

  /// Consumer key of the Salesforce Connected App.
  final String clientId;

  /// Must exactly match a callback URL configured on the Connected App. A
  /// custom scheme (`luxestays://oauth/callback`) keeps the redirect off the
  /// public web.
  final String redirectUri;
  final String loginBaseUrl;
  final List<String> scopes;

  String get authorizeEndpoint => '$loginBaseUrl/services/oauth2/authorize';
  String get tokenEndpoint => '$loginBaseUrl/services/oauth2/token';
  String get userInfoEndpoint => '$loginBaseUrl/services/oauth2/userinfo';
  String get revokeEndpoint => '$loginBaseUrl/services/oauth2/revoke';

  /// Creates a one-shot PKCE challenge. The verifier stays on the device; only
  /// its SHA-256 hash travels in the authorize URL.
  static PkcePair createPkcePair() {
    final Random random = Random.secure();
    final List<int> bytes =
        List<int>.generate(64, (_) => random.nextInt(256), growable: false);
    final String verifier = base64UrlEncode(bytes).replaceAll('=', '');
    final String challenge =
        base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes)
            .replaceAll('=', '');
    return PkcePair(verifier: verifier, challenge: challenge);
  }

  Uri buildAuthorizationUrl({
    required PkcePair pkce,
    required String state,
    String? loginHint,
  }) {
    return Uri.parse(authorizeEndpoint).replace(
      queryParameters: <String, String>{
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'scope': scopes.join(' '),
        'code_challenge': pkce.challenge,
        'code_challenge_method': 'S256',
        'state': state,
        if (loginHint != null) 'login_hint': loginHint,
        // Forces the account chooser rather than silently reusing a session
        // that belongs to somebody else on a shared device.
        'prompt': 'login',
      },
    );
  }

  /// Exchanges the authorization code for tokens.
  ///
  /// Note the absence of a client secret: that is the entire point of PKCE.
  Future<OAuthTokens> exchangeCode({
    required String code,
    required PkcePair pkce,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      tokenEndpoint,
      data: <String, String>{
        'grant_type': 'authorization_code',
        'code': code,
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'code_verifier': pkce.verifier,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        extra: <String, Object?>{'skipAuth': true},
      ),
    );
    final OAuthTokens tokens = _tokensFrom(response.data);
    await _store.write(TokenKeys.salesforce, tokens);
    _logger.info('salesforce: authorization code exchanged');
    return tokens;
  }

  /// Refreshes using the stored refresh token. Returns null when there is
  /// nothing to refresh with, which `AuthInterceptor` treats as "signed out".
  Future<OAuthTokens?> refresh() async {
    final OAuthTokens? current = await _store.read(TokenKeys.salesforce);
    final String? refreshToken = current?.refreshToken;
    if (refreshToken == null) {
      _logger.warn('salesforce: no refresh token, cannot renew session');
      return null;
    }
    final Response<dynamic> response = await _dio.post<dynamic>(
      tokenEndpoint,
      data: <String, String>{
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': clientId,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        extra: <String, Object?>{'skipAuth': true},
      ),
    );
    // Salesforce does not re-issue the refresh token on every rotation, so
    // carry the old one forward when the response omits it.
    final OAuthTokens tokens = _tokensFrom(
      response.data,
      fallbackRefreshToken: refreshToken,
    );
    await _store.write(TokenKeys.salesforce, tokens);
    return tokens;
  }

  Future<void> signOut() async {
    final OAuthTokens? current = await _store.read(TokenKeys.salesforce);
    await _store.delete(TokenKeys.salesforce);
    if (current == null) {
      return;
    }
    try {
      await _dio.post<dynamic>(
        revokeEndpoint,
        data: <String, String>{'token': current.accessToken},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          extra: <String, Object?>{'skipAuth': true},
        ),
      );
    } catch (e) {
      // A failed revoke must not block sign-out locally; the token is already
      // gone from the keychain and will expire on its own.
      _logger.warn('salesforce: revoke failed (ignored)', error: e);
    }
  }

  OAuthTokens _tokensFrom(Object? data, {String? fallbackRefreshToken}) {
    final Map<String, Object?> json = data is Map<String, Object?>
        ? data
        : jsonDecode(data.toString()) as Map<String, Object?>;
    final Object? expiresIn = json['expires_in'];
    final Duration lifetime = expiresIn is num
        ? Duration(seconds: expiresIn.toInt())
        : const Duration(hours: 2);
    return OAuthTokens(
      accessToken: json['access_token']! as String,
      refreshToken: (json['refresh_token'] as String?) ?? fallbackRefreshToken,
      instanceUrl: json['instance_url'] as String?,
      tokenType: (json['token_type'] as String?) ?? 'Bearer',
      expiresAt: DateTime.now().toUtc().add(lifetime),
    );
  }
}

class PkcePair {
  const PkcePair({required this.verifier, required this.challenge});

  final String verifier;
  final String challenge;
}
