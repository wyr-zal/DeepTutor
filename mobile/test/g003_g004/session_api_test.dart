import 'dart:typed_data';

import 'package:deeptutor_mobile/api/api_client.dart';
import 'package:deeptutor_mobile/api/session_api.dart';
import 'package:deeptutor_mobile/models/session_summary.dart';
import 'package:deeptutor_mobile/services/auth_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? request;
  String responseBody = '{"sessions":[]}';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      responseBody,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _EmptySecureStore implements SecureKeyValueStore {
  @override
  Future<void> delete(String key) async {}

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String? value) async {}
}

void main() {
  test('parses wrapped session summaries and query contract', () async {
    String? requestedPath;
    Map<String, dynamic>? requestedQuery;
    final api = SessionApi(
      loadJson: (path, {queryParameters}) async {
        requestedPath = path;
        requestedQuery = queryParameters;
        return <String, Object?>{
          'sessions': <Object?>[
            <String, Object?>{
              'session_id': 'session-1',
              'title': '二次函数复习',
              'capability': 'deep_question',
              'status': 'idle',
              'message_count': 4,
              'last_message': '请再解释顶点式。',
              'created_at': 1785225600.0,
              'updated_at': '2026-07-29T08:30:00Z',
            },
          ],
        };
      },
    );

    final sessions = await api.listSessions(limit: 25, offset: 50);

    expect(requestedPath, '/api/v1/sessions');
    expect(requestedQuery, <String, dynamic>{'limit': 25, 'offset': 50});
    expect(sessions, hasLength(1));
    expect(sessions.single.id, 'session-1');
    expect(sessions.single.messageCount, 4);
    expect(sessions.single.capability, 'deep_question');
    expect(sessions.single.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1785225600000, isUtc: true));
    expect(sessions.single.updatedAt, DateTime.utc(2026, 7, 29, 8, 30));
  });

  test('rejects malformed wrapper and invalid pagination', () async {
    final malformed = SessionApi(
      loadJson: (_, {queryParameters}) async => <String, Object?>{'items': []},
    );

    expect(malformed.listSessions, throwsFormatException);
    expect(() => malformed.listSessions(limit: 0), throwsRangeError);
    expect(() => malformed.listSessions(offset: -1), throwsRangeError);
    expect(
      () => SessionSummary.fromJson(<String, Object?>{'title': 'missing id'}),
      throwsFormatException,
    );
  });

  test('fromDio preserves a deployment path prefix', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final api = SessionApi.fromDio(
      dio,
      baseUrl: 'https://tutor.example.com/deeptutor',
    );

    await api.listSessions(limit: 12, offset: 3);

    expect(
      adapter.request?.uri.toString(),
      'https://tutor.example.com/deeptutor/api/v1/sessions?limit=12&offset=3',
    );
    dio.close();
  });

  test('fromApiClient serializes numeric pagination values', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final client = ApiClient(
      authStore: AuthStore(_EmptySecureStore()),
      dio: dio,
    );
    final api = SessionApi.fromApiClient(
      client,
      baseUrl: 'https://tutor.example.com/deeptutor',
    );

    await api.listSessions(limit: 12, offset: 3);

    expect(
      adapter.request?.uri.toString(),
      'https://tutor.example.com/deeptutor/api/v1/sessions?limit=12&offset=3',
    );
    client.dispose();
  });

  test('parses session detail messages and persisted event metadata', () async {
    final api = SessionApi(
      loadJson: (path, {queryParameters}) async {
        expect(path, '/api/v1/sessions/session-1');
        return <String, Object?>{
          'session_id': 'session-1',
          'title': '函数复习',
          'messages': <Object?>[
            <String, Object?>{
              'id': 1,
              'role': 'assistant',
              'content': '题目如下',
              'capability': 'deep_question',
              'metadata': <String, Object?>{'branch': 'main'},
              'events': <Object?>[
                <String, Object?>{
                  'type': 'content',
                  'metadata': <String, Object?>{
                    'call_kind': 'quiz_question_emitted',
                  },
                },
              ],
            },
          ],
        };
      },
    );

    final detail = await api.getSession('session-1');

    expect(detail.title, '函数复习');
    expect(detail.messages.single.id, '1');
    expect(detail.messages.single.capability, 'deep_question');
    expect(detail.messages.single.events.single['type'], 'content');
  });

  test('rename and delete use PATCH/DELETE with strict paths', () async {
    final writes = <Map<String, Object?>>[];
    final api = SessionApi(
      loadJson: (_, {queryParameters}) async => <String, Object?>{
        'sessions': <Object?>[],
      },
      writeJson: (method, path, {data}) async {
        writes.add(<String, Object?>{
          'method': method,
          'path': path,
          'data': data,
        });
        return <String, Object?>{};
      },
    );

    await api.renameSession('session-1', '  新标题  ');
    await api.deleteSession('session-1');

    expect(writes, <Map<String, Object?>>[
      <String, Object?>{
        'method': 'PATCH',
        'path': '/api/v1/sessions/session-1',
        'data': <String, Object?>{'title': '新标题'},
      },
      <String, Object?>{
        'method': 'DELETE',
        'path': '/api/v1/sessions/session-1',
        'data': null,
      },
    ]);
  });

  test('fromApiClient sends PATCH and DELETE through the authenticated client',
      () async {
    final adapter = _RecordingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final client = ApiClient(
      authStore: AuthStore(_EmptySecureStore()),
      dio: dio,
    );
    final api = SessionApi.fromApiClient(
      client,
      baseUrl: 'https://tutor.example.com/deeptutor',
    );

    await api.renameSession('session-1', '标题');
    expect(adapter.request?.method, 'PATCH');
    expect(
      adapter.request?.uri.toString(),
      'https://tutor.example.com/deeptutor/api/v1/sessions/session-1',
    );

    await api.deleteSession('session-1');
    expect(adapter.request?.method, 'DELETE');
    client.dispose();
  });
}
