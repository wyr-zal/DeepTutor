import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/auth_session.dart';

abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String? value);

  Future<void> delete(String key);
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class AuthStore {
  AuthStore(this._storage);

  static const _baseUrlKey = 'auth.base_url';
  static const _accessTokenKey = 'auth.access_token';
  static const _tokenTypeKey = 'auth.token_type';
  static const _expiresInKey = 'auth.expires_in';
  static const _userKey = 'auth.user';
  static const _authEnabledKey = 'auth.enabled';

  final SecureKeyValueStore _storage;

  Future<String?> readBaseUrl() => _storage.read(_baseUrlKey);

  Future<String?> readAccessToken() => _storage.read(_accessTokenKey);

  Future<void> saveBaseUrl(String baseUrl) =>
      _storage.write(_baseUrlKey, baseUrl);

  Future<void> saveSession(AuthSession session) async {
    await Future.wait(<Future<void>>[
      _storage.write(_baseUrlKey, session.baseUrl),
      _storage.write(_accessTokenKey, session.accessToken),
      _storage.write(_tokenTypeKey, session.tokenType),
      _storage.write(_expiresInKey, session.expiresIn?.toString()),
      _storage.write(_userKey, jsonEncode(session.user.toJson())),
      _storage.write(_authEnabledKey, session.authEnabled.toString()),
    ]);
  }

  Future<AuthSession?> readSession() async {
    final values = await Future.wait<String?>(<Future<String?>>[
      _storage.read(_baseUrlKey),
      _storage.read(_accessTokenKey),
      _storage.read(_tokenTypeKey),
      _storage.read(_expiresInKey),
      _storage.read(_userKey),
      _storage.read(_authEnabledKey),
    ]);
    final baseUrl = values[0];
    final authEnabled = values[5] != 'false';
    if (baseUrl == null || baseUrl.isEmpty) {
      return null;
    }
    if (authEnabled && (values[1] == null || values[1]!.isEmpty)) {
      return null;
    }

    try {
      final rawUser = jsonDecode(values[4] ?? '');
      if (rawUser is! Map) {
        return null;
      }
      return AuthSession(
        baseUrl: baseUrl,
        accessToken: values[1],
        tokenType: values[2] ?? 'bearer',
        expiresIn: int.tryParse(values[3] ?? ''),
        user: AuthUser.fromJson(Map<String, dynamic>.from(rawUser)),
        authEnabled: authEnabled,
      );
    } catch (_) {
      return null;
    }
  }

  /// Removes credentials and user identity while optionally retaining the
  /// last server address for a friendlier next login.
  Future<void> clearSession({bool keepBaseUrl = true}) async {
    await Future.wait(<Future<void>>[
      _storage.delete(_accessTokenKey),
      _storage.delete(_tokenTypeKey),
      _storage.delete(_expiresInKey),
      _storage.delete(_userKey),
      _storage.delete(_authEnabledKey),
      if (!keepBaseUrl) _storage.delete(_baseUrlKey),
    ]);
  }
}

final secureKeyValueStoreProvider = Provider<SecureKeyValueStore>(
  (ref) => FlutterSecureKeyValueStore(),
);

final authStoreProvider = Provider<AuthStore>(
  (ref) => AuthStore(ref.watch(secureKeyValueStoreProvider)),
);
