import 'dart:typed_data';

import 'package:deeptutor_mobile/api/api_client.dart';
import 'package:deeptutor_mobile/models/auth_session.dart';
import 'package:deeptutor_mobile/services/auth_store.dart';
import 'package:dio/dio.dart';
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

class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter(this.statusCode);

  final int statusCode;
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      statusCode == 401 ? '{"detail":"expired"}' : '{}',
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
  late AuthStore store;

  setUp(() async {
    store = AuthStore(MemorySecureStore());
    await store.saveSession(
      const AuthSession(
        baseUrl: 'https://tutor.example.com',
        accessToken: 'secret-jwt',
        tokenType: 'bearer',
        expiresIn: 3600,
        user: AuthUser(
          id: 'u_1',
          username: 'learner',
          role: 'user',
          isAdmin: false,
        ),
        authEnabled: true,
      ),
    );
  });

  test('adds Bearer token only for the configured server', () async {
    final adapter = RecordingAdapter(200);
    final dio = Dio()..httpClientAdapter = adapter;
    final client = ApiClient(authStore: store, dio: dio);

    await client.get<dynamic>(
      'https://tutor.example.com',
      '/api/v1/auth/status',
    );
    expect(adapter.request?.headers['Authorization'], 'Bearer secret-jwt');

    await client.get<dynamic>(
      'https://other.example.com',
      '/api/v1/auth/status',
    );
    expect(adapter.request?.headers['Authorization'], isNull);
    client.dispose();
  });

  test('emits a signal for HTTP 401', () async {
    final adapter = RecordingAdapter(401);
    final dio = Dio()..httpClientAdapter = adapter;
    final client = ApiClient(authStore: store, dio: dio);
    final event = client.unauthorizedEvents.first;

    await expectLater(
      client.get<dynamic>('https://tutor.example.com', '/api/v1/knowledge'),
      throwsA(isA<DioException>()),
    );

    expect((await event).uri.host, 'tutor.example.com');
    client.dispose();
  });
}
