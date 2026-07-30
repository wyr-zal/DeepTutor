import 'dart:convert';
import 'dart:typed_data';

import 'package:deeptutor_mobile/api/api_client.dart';
import 'package:deeptutor_mobile/config/app_config.dart';
import 'package:deeptutor_mobile/features/auth/auth_controller.dart';
import 'package:deeptutor_mobile/features/auth/server_connection_controller.dart';
import 'package:deeptutor_mobile/services/auth_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

class JsonAdapter implements HttpClientAdapter {
  JsonAdapter(this.responses);

  final Map<String, Map<String, dynamic>> responses;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body = responses['${options.method} ${options.uri.path}'] ??
        const <String, dynamic>{};
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class ExpiringSessionAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path == '/api/v1/auth/status') {
      return _jsonResponse(<String, Object>{
        'enabled': true,
        'authenticated': false,
      });
    }
    if (options.uri.path == '/api/v1/auth/token') {
      return _jsonResponse(<String, Object>{
        'access_token': 'expired-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': <String, Object>{
          'user_id': 'u_1',
          'username': 'learner',
          'role': 'user',
          'is_admin': false,
        },
      });
    }
    return ResponseBody.fromString(
      '{"detail":"expired"}',
      401,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  static ResponseBody _jsonResponse(Map<String, Object> body) {
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('personal fixed server bootstraps a local session without probing',
      () async {
    final storage = MemorySecureStore();
    final store = AuthStore(storage);
    final adapter = JsonAdapter(<String, Map<String, dynamic>>{});
    final client = ApiClient(
      authStore: store,
      dio: Dio()..httpClientAdapter = adapter,
    );
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(storage),
        apiClientProvider.overrideWithValue(client),
        appConnectionConfigProvider.overrideWithValue(
          const AppConnectionConfig(
            fixedServerUrl: 'https://deeptutor.cliproxy.com.cn/',
            personalServerMode: true,
          ),
        ),
      ],
    );
    addTearDown(() {
      container.dispose();
      client.dispose();
    });

    await container.read(authControllerProvider.notifier).bootstrap();

    final session = container.read(authControllerProvider).requireValue;
    expect(session?.baseUrl, 'https://deeptutor.cliproxy.com.cn');
    expect(session?.authEnabled, isFalse);
    expect(session?.user.id, 'local-admin');
    expect(await store.readBaseUrl(), 'https://deeptutor.cliproxy.com.cn');
    expect(adapter.requests, isEmpty);
  });

  test('personal fixed server reports auth-enabled deployments in health state',
      () async {
    final storage = MemorySecureStore();
    final store = AuthStore(storage);
    final adapter = JsonAdapter(<String, Map<String, dynamic>>{
      'GET /api/v1/auth/status': <String, dynamic>{
        'enabled': true,
        'authenticated': false,
      },
    });
    final client = ApiClient(
      authStore: store,
      dio: Dio()..httpClientAdapter = adapter,
    );
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(storage),
        apiClientProvider.overrideWithValue(client),
        appConnectionConfigProvider.overrideWithValue(
          const AppConnectionConfig(
            fixedServerUrl: 'https://deeptutor.cliproxy.com.cn',
            personalServerMode: true,
          ),
        ),
      ],
    );
    addTearDown(() {
      container.dispose();
      client.dispose();
    });

    await container.read(authControllerProvider.notifier).bootstrap();
    final connection =
        await container.read(serverConnectionControllerProvider.future);

    final state = container.read(authControllerProvider);
    expect(state.requireValue?.baseUrl, 'https://deeptutor.cliproxy.com.cn');
    expect(state.requireValue?.authEnabled, isFalse);
    expect(connection.status, ServerConnectionStatus.authMisconfigured);
    expect(connection.message, contains('auth.enabled=false'));
    expect(await store.readAccessToken(), isNull);
  });

  test('auth-disabled bootstrap creates a durable no-token session', () async {
    final storage = MemorySecureStore();
    final store = AuthStore(storage);
    await store.saveBaseUrl('http://10.0.2.2:8001');
    final adapter = JsonAdapter(<String, Map<String, dynamic>>{
      'GET /api/v1/auth/status': <String, dynamic>{
        'enabled': false,
        'authenticated': true,
        'user_id': 'local-admin',
        'username': 'local',
        'role': 'admin',
        'is_admin': true,
      },
    });
    final client = ApiClient(
      authStore: store,
      dio: Dio()..httpClientAdapter = adapter,
    );
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(storage),
        apiClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(() {
      container.dispose();
      client.dispose();
    });

    await container.read(authControllerProvider.notifier).bootstrap();

    final session = container.read(authControllerProvider).requireValue;
    expect(session?.authEnabled, isFalse);
    expect(session?.hasAccessToken, isFalse);
    expect((await store.readSession())?.user.username, 'local');
  });

  test(
    'login probes status then parses and stores the nested token response',
    () async {
      final storage = MemorySecureStore();
      final store = AuthStore(storage);
      final adapter = JsonAdapter(<String, Map<String, dynamic>>{
        'GET /api/v1/auth/status': <String, dynamic>{
          'enabled': true,
          'authenticated': false,
        },
        'POST /api/v1/auth/token': <String, dynamic>{
          'access_token': 'new-token',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': <String, dynamic>{
            'user_id': 'u_1',
            'username': 'learner',
            'role': 'user',
            'is_admin': false,
          },
        },
      });
      final client = ApiClient(
        authStore: store,
        dio: Dio()..httpClientAdapter = adapter,
      );
      final container = ProviderContainer(
        overrides: [
          secureKeyValueStoreProvider.overrideWithValue(storage),
          apiClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(() {
        container.dispose();
        client.dispose();
      });

      final session =
          await container.read(authControllerProvider.notifier).login(
                baseUrl: 'tutor.example.com/',
                username: 'learner',
                password: 'password',
              );

      expect(session.baseUrl, 'https://tutor.example.com');
      expect(session.accessToken, 'new-token');
      expect(session.user.username, 'learner');
      expect(await store.readAccessToken(), 'new-token');
      expect(adapter.requests.map((request) => request.method), <String>[
        'GET',
        'POST',
      ]);
    },
  );

  test('same-server 401 clears the stored session and signs out', () async {
    final storage = MemorySecureStore();
    final store = AuthStore(storage);
    final client = ApiClient(
      authStore: store,
      dio: Dio()..httpClientAdapter = ExpiringSessionAdapter(),
    );
    final container = ProviderContainer(
      overrides: [
        secureKeyValueStoreProvider.overrideWithValue(storage),
        apiClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(() {
      container.dispose();
      client.dispose();
    });

    await container.read(authControllerProvider.notifier).login(
          baseUrl: 'https://tutor.example.com',
          username: 'learner',
          password: 'password',
        );
    expect(await store.readAccessToken(), 'expired-token');

    // The next same-server request simulates an expired JWT.
    await expectLater(
      client.get<dynamic>(
        'https://tutor.example.com',
        '/api/v1/knowledge/list',
      ),
      throwsA(isA<DioException>()),
    );
    await Future<void>.delayed(Duration.zero);

    expect(await store.readAccessToken(), isNull);
    expect(container.read(authControllerProvider).valueOrNull, isNull);
  });
}
