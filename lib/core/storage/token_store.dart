import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// An OAuth token set as returned by the Salesforce token endpoint.
class OAuthTokens {
  const OAuthTokens({
    required this.accessToken,
    required this.expiresAt,
    this.refreshToken,
    this.instanceUrl,
    this.tokenType = 'Bearer',
  });

  factory OAuthTokens.fromJson(Map<String, Object?> json) {
    final Object? expires = json['expiresAt'];
    return OAuthTokens(
      accessToken: json['accessToken']! as String,
      refreshToken: json['refreshToken'] as String?,
      instanceUrl: json['instanceUrl'] as String?,
      tokenType: (json['tokenType'] as String?) ?? 'Bearer',
      expiresAt: DateTime.parse(expires! as String),
    );
  }

  final String accessToken;
  final String? refreshToken;
  final String? instanceUrl;
  final String tokenType;
  final DateTime expiresAt;

  /// Treat a token as expired 60s early so a request never dies in flight.
  bool get isExpired => DateTime.now().toUtc().isAfter(
    expiresAt.subtract(const Duration(seconds: 60)),
  );

  String get authorizationHeader => '$tokenType $accessToken';

  Map<String, Object?> toJson() => <String, Object?>{
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'instanceUrl': instanceUrl,
    'tokenType': tokenType,
    'expiresAt': expiresAt.toIso8601String(),
  };
}

/// Where access/refresh tokens live.
///
/// Interface first, so tests use [InMemoryTokenStore] and never touch the
/// platform keychain (which is unavailable in a `flutter test` VM).
abstract interface class TokenStore {
  Future<OAuthTokens?> read(String key);
  Future<void> write(String key, OAuthTokens tokens);
  Future<void> delete(String key);
  Future<void> clear();
}

/// Keychain (iOS) / platform encrypted storage (Android) backed store.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<OAuthTokens?> read(String key) async {
    final String? raw = await _storage.read(key: key);
    if (raw == null) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Invalid token data');
      }
      return OAuthTokens.fromJson(decoded);
    } on FormatException {
      await _storage.delete(key: key);
      return null;
    } on TypeError {
      await _storage.delete(key: key);
      return null;
    }
  }

  @override
  Future<void> write(String key, OAuthTokens tokens) =>
      _storage.write(key: key, value: jsonEncode(tokens.toJson()));

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> clear() => _storage.deleteAll();
}

/// Test / preview double.
class InMemoryTokenStore implements TokenStore {
  final Map<String, OAuthTokens> _values = <String, OAuthTokens>{};

  @override
  Future<OAuthTokens?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, OAuthTokens tokens) async {
    _values[key] = tokens;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> clear() async => _values.clear();
}

abstract final class TokenKeys {
  static const String salesforce = 'salesforce_oauth';
  static const String synxis = 'synxis_oauth';
  static const String bff = 'bff_session';
}
