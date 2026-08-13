import 'dart:convert';
import 'dart:typed_data';

import 'package:deeptutor_mobile/api/api_client.dart';
import 'package:deeptutor_mobile/app/app.dart';
import 'package:deeptutor_mobile/config/app_config.dart';
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
          appConnectionConfigProvider.overrideWithValue(
            const AppConnectionConfig(
              fixedServerUrl: 'https://tutor.example.com',
              manualServerEntryEnabled: false,
            ),
          ),
        ],
        child: const DeepTutorApp(),
      ),
    );
    await tester.pumpAndSettle();

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

    expect(find.text('登录 DeepTutor'), findsOneWidget);
    expect(find.text('用户名或密码不正确'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
  });
}
