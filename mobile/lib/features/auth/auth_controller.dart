import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/auth_api.dart';
import '../../config/app_config.dart';
import '../../config/server_url.dart';
import '../../models/auth_session.dart';
import '../../services/auth_store.dart';

class AuthController extends AsyncNotifier<AuthSession?> {
  StreamSubscription<UnauthorizedEvent>? _unauthorizedSubscription;

  AuthStore get _store => ref.read(authStoreProvider);
  AuthApi get _api => ref.read(authApiProvider);

  @override
  AuthSession? build() {
    _unauthorizedSubscription ??= ref
        .read(apiClientProvider)
        .unauthorizedEvents
        .listen(_handleUnauthorized);
    ref.onDispose(() => _unauthorizedSubscription?.cancel());
    return null;
  }

  Future<void> bootstrap() async {
    try {
      final config = ref.read(appConnectionConfigProvider);
      var stored = await _store.readSession();
      final fixedBaseUrl = config.normalizedFixedServerUrl();
      final storedBaseUrl = stored?.baseUrl ?? await _store.readBaseUrl();
      final baseUrl = fixedBaseUrl ?? storedBaseUrl;
      if (baseUrl == null || baseUrl.isEmpty) {
        if (config.personalServerMode) {
          throw const AuthApiException('单人固定服务器模式缺少服务器地址。');
        }
        state = const AsyncData(null);
        return;
      }

      if (fixedBaseUrl != null && storedBaseUrl != fixedBaseUrl) {
        await _store.clearSession(keepBaseUrl: false);
        await _store.saveBaseUrl(fixedBaseUrl);
        stored = null;
      }

      if (fixedBaseUrl != null && config.personalServerMode) {
        final session = AuthSession.local(baseUrl: fixedBaseUrl);
        await _store.saveSession(session);
        state = AsyncData(session);
        return;
      }

      state = const AsyncLoading();
      final status = await _api.status(baseUrl);
      if (status.enabled && config.personalServerMode) {
        await _store.clearSession(keepBaseUrl: fixedBaseUrl != null);
        throw const AuthApiException(
            '固定服务器已启用身份认证，请先将服务端 auth.enabled 设置为 false。');
      }
      if (!status.enabled) {
        final session = AuthSession.local(baseUrl: baseUrl, user: status.user);
        await _store.saveSession(session);
        state = AsyncData(session);
        return;
      }

      if (stored != null && stored.hasAccessToken && status.authenticated) {
        final session = status.user == null
            ? stored
            : AuthSession(
                baseUrl: stored.baseUrl,
                accessToken: stored.accessToken,
                tokenType: stored.tokenType,
                expiresIn: stored.expiresIn,
                user: status.user!,
                authEnabled: true,
              );
        await _store.saveSession(session);
        state = AsyncData(session);
      } else {
        await _store.clearSession();
        state = const AsyncData(null);
      }
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  Future<AuthSession> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final normalizedBaseUrl = normalizeServerUrl(baseUrl);
    final previousBaseUrl = await _store.readBaseUrl();
    if (previousBaseUrl != null && previousBaseUrl != normalizedBaseUrl) {
      // Never carry credentials from one user-entered server to another.
      await _store.clearSession(keepBaseUrl: false);
    }
    await _store.saveBaseUrl(normalizedBaseUrl);
    state = const AsyncLoading();

    try {
      final status = await _api.status(normalizedBaseUrl);
      final AuthSession session;
      if (!status.enabled) {
        session = AuthSession.local(
          baseUrl: normalizedBaseUrl,
          user: status.user,
        );
      } else {
        if (username.trim().isEmpty || password.isEmpty) {
          throw const FormatException('请输入用户名和密码');
        }
        session = await _api.login(
          baseUrl: normalizedBaseUrl,
          username: username.trim(),
          password: password,
        );
      }
      await _store.saveSession(session);
      state = AsyncData(session);
      return session;
    } catch (_) {
      // Login errors belong to the form. Restoring the signed-out state keeps
      // the page mounted so it can show the actionable 401/network message.
      state = const AsyncData(null);
      rethrow;
    }
  }

  Future<void> logout() async {
    await _store.clearSession();
    state = const AsyncData(null);
  }

  Future<void> forgetServer() async {
    await _store.clearSession(keepBaseUrl: false);
    state = const AsyncData(null);
  }

  Future<void> _handleUnauthorized(UnauthorizedEvent event) async {
    final session = state.asData?.value;
    if (session == null || !session.hasAccessToken) {
      return;
    }
    final eventOrigin = event.uri.replace(path: '', query: '', fragment: '');
    final serverOrigin = Uri.parse(
      session.baseUrl,
    ).replace(path: '', query: '', fragment: '');
    if (eventOrigin != serverOrigin) {
      return;
    }
    await _store.clearSession();
    state = const AsyncData(null);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

/// Trigger this provider once from app startup/router setup. It restores a
/// saved session and validates it against `/api/v1/auth/status`.
final authBootstrapProvider = FutureProvider<void>((ref) async {
  await ref.read(authControllerProvider.notifier).bootstrap();
});
