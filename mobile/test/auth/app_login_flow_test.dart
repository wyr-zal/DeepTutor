import 'dart:convert';
import 'dart:typed_data';

import 'package:deeptutor_mobile/api/api_client.dart';
import 'package:deeptutor_mobile/app/app.dart';
import 'package:deeptutor_mobile/config/app_config.dart';
import 'package:deeptutor_mobile/features/auth/transport_diagnostics_controller.dart';
import 'package:deeptutor_mobile/features/home/knowledge_list_controller.dart';
import 'package:deeptutor_mobile/models/knowledge_base.dart';
import 'package:deeptutor_mobile/services/knowledge_cache_store.dart';
import 'package:deeptutor_mobile/services/auth_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

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

class _LoginAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/api/v1/auth/status')) {
      return _json(<String, Object?>{
        'enabled': true,
        'authenticated': false,
      });
    }
    if (options.path.endsWith('/api/v1/auth/token')) {
      return _json(
        <String, Object?>{'detail': 'Invalid credentials'},
        statusCode: 401,
      );
    }
    return _json(<String, Object?>{}, statusCode: 404);
  }

  ResponseBody _json(
    Map<String, Object?> body, {
    int statusCode = 200,
  }) {
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _OfflineAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      error: 'offline',
    );
  }

  @override
  void close({bool force = false}) {}
}

class _CachedKnowledgeStore extends KnowledgeCacheStore {
  _CachedKnowledgeStore(this.cached)
      : super(namespace: 'test-fixed-offline-app');

  final CachedKnowledgeBases? cached;

  @override
  Future<CachedKnowledgeBases?> read() async => cached;

  @override
  Future<void> write({
    required List<KnowledgeBase> items,
    required String serverUrl,
    required String userId,
    DateTime? lastSyncedAt,
  }) async {}
}

void main() {
  testWidgets('wrong password keeps the login form mounted and shows 401', (
    tester,
  ) async {
    final storage = _MemorySecureStore();
    final client = ApiClient(
      authStore: AuthStore(storage),
      dio: Dio()..httpClientAdapter = _LoginAdapter(),
    );
    addTearDown(client.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          secureKeyValueStoreProvider.overrideWithValue(storage),
          apiClientProvider.overrideWithValue(client),
        ],
        child: const DeepTutorApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, '服务器地址'),
      'https://tutor.example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '用户名'),
      'learner',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '密码'),
      'wrong',
    );
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.text('连接 DeepTutor'), findsOneWidget);
    expect(find.text('用户名或密码不正确'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
  });

  testWidgets(
      'fixed personal mode opens the app shell when the server is offline',
      (tester) async {
    final storage = _MemorySecureStore();
    final store = AuthStore(storage);
    final adapter = _OfflineAdapter();
    final client = ApiClient(
      authStore: store,
      dio: Dio()..httpClientAdapter = adapter,
    );
    addTearDown(client.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          secureKeyValueStoreProvider.overrideWithValue(storage),
          apiClientProvider.overrideWithValue(client),
          appConnectionConfigProvider.overrideWithValue(
            const AppConnectionConfig(
              fixedServerUrl: 'https://deeptutor.cliproxy.com.cn/',
              personalServerMode: true,
            ),
          ),
          knowledgeCacheStoreProvider.overrideWith(
            (ref, namespace) => _CachedKnowledgeStore(null),
          ),
          transportDiagnosticsProvider.overrideWith((ref) async {
            return const TransportDiagnosticsReport(
              steps: <TransportDiagnosticStep>[
                TransportDiagnosticStep.failed(
                  name: 'TCP host:443',
                  detail: 'SocketException: Connection reset by peer',
                  elapsedMs: 123,
                ),
              ],
            );
          }),
        ],
        child: const DeepTutorApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DeepTutor'), findsOneWidget);
    expect(find.text('离线浏览缓存'), findsOneWidget);
    expect(find.text('暂无已同步题库'), findsOneWidget);
    expect(find.text('重试同步'), findsWidgets);
    expect(find.text('连接 DeepTutor'), findsNothing);
    expect(find.text('无法连接已保存的服务器'), findsNothing);
    expect(find.text('重新填写服务器地址'), findsNothing);
    expect(await store.readBaseUrl(), 'https://deeptutor.cliproxy.com.cn');
    expect(
      adapter.requests.map((request) => request.uri.path),
      contains('/api/v1/auth/status'),
    );
    expect(
      adapter.requests.map((request) => request.uri.path),
      contains('/api/v1/knowledge/list'),
    );
  });

  testWidgets('diagnostic mode renders sanitized mobile network details',
      (tester) async {
    final storage = _MemorySecureStore();
    final adapter = _OfflineAdapter();
    final client = ApiClient(
      authStore: AuthStore(storage),
      dio: Dio()..httpClientAdapter = adapter,
    );
    addTearDown(client.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          secureKeyValueStoreProvider.overrideWithValue(storage),
          apiClientProvider.overrideWithValue(client),
          appConnectionConfigProvider.overrideWithValue(
            const AppConnectionConfig(
              fixedServerUrl: 'https://deeptutor.cliproxy.com.cn/',
              personalServerMode: true,
              diagnosticsEnabled: true,
            ),
          ),
          knowledgeCacheStoreProvider.overrideWith(
            (ref, namespace) => _CachedKnowledgeStore(null),
          ),
          transportDiagnosticsProvider.overrideWith((ref) async {
            return const TransportDiagnosticsReport(
              steps: <TransportDiagnosticStep>[
                TransportDiagnosticStep.failed(
                  name: 'TCP host:443',
                  detail: 'SocketException: Connection reset by peer',
                  elapsedMs: 123,
                ),
              ],
            );
          }),
        ],
        child: const DeepTutorApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('诊断模式'), findsOneWidget);
    expect(find.textContaining('[auth/status]'), findsOneWidget);
    expect(find.textContaining('[knowledge/list]'), findsOneWidget);
    expect(find.textContaining('type=connectionError'), findsWidgets);
    expect(find.textContaining('api/v1/auth/status'), findsOneWidget);
    expect(find.textContaining('api/v1/knowledge/list'), findsOneWidget);
    expect(find.textContaining('[transport]'), findsOneWidget);
    expect(find.textContaining('TCP host:443'), findsOneWidget);
    expect(find.textContaining('Authorization'), findsNothing);
  });
}
