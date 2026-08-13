import 'package:dio/dio.dart';

import '../config/server_url.dart';
import '../models/session_detail.dart';
import '../models/session_summary.dart';
import 'api_client.dart';

typedef SessionJsonLoader = Future<Object?> Function(
  String path, {
  Map<String, dynamic>? queryParameters,
});

typedef SessionJsonWriter = Future<Object?> Function(
  String method,
  String path, {
  Object? data,
});

abstract interface class SessionRepository {
  Future<List<SessionSummary>> listSessions({int limit = 50, int offset = 0});
}

class SessionSyncPage {
  const SessionSyncPage({
    required this.cursor,
    required this.sessions,
    required this.deletedSessionIds,
    required this.hasMore,
    required this.incremental,
  });

  final int cursor;
  final List<SessionSummary> sessions;
  final List<String> deletedSessionIds;
  final bool hasMore;
  final bool incremental;
}

class SessionApi implements SessionRepository {
  SessionApi({
    required SessionJsonLoader loadJson,
    SessionJsonWriter? writeJson,
  })  : _loadJson = loadJson,
        _writeJson = writeJson;

  factory SessionApi.fromApiClient(
    ApiClient client, {
    required String baseUrl,
  }) {
    return SessionApi(
      loadJson: (path, {queryParameters}) async {
        final response = await client.get<Object?>(
          baseUrl,
          path,
          queryParameters: queryParameters,
        );
        return response.data;
      },
      writeJson: (method, path, {data}) async {
        final response = switch (method) {
          'PATCH' => await client.patch<Object?>(baseUrl, path, data: data),
          'DELETE' => await client.delete<Object?>(baseUrl, path, data: data),
          _ => throw UnsupportedError('Unsupported session method: $method'),
        };
        return response.data;
      },
    );
  }

  factory SessionApi.fromDio(Dio dio, {required String baseUrl}) {
    return SessionApi(
      loadJson: (path, {queryParameters}) async {
        final uri = resolveServerUri(baseUrl, path).replace(
          queryParameters: queryParameters?.map(
            (key, value) => MapEntry(key, value.toString()),
          ),
        );
        final response = await dio.getUri<Object?>(
          uri,
        );
        return response.data;
      },
      writeJson: (method, path, {data}) async {
        final uri = resolveServerUri(baseUrl, path);
        final response = switch (method) {
          'PATCH' => await dio.patchUri<Object?>(uri, data: data),
          'DELETE' => await dio.deleteUri<Object?>(uri, data: data),
          _ => throw UnsupportedError('Unsupported session method: $method'),
        };
        return response.data;
      },
    );
  }

  static const listPath = '/api/v1/sessions';

  final SessionJsonLoader _loadJson;
  final SessionJsonWriter? _writeJson;

  @override
  Future<List<SessionSummary>> listSessions({
    int limit = 50,
    int offset = 0,
  }) async {
    if (limit < 1 || limit > 200) {
      throw RangeError.range(limit, 1, 200, 'limit');
    }
    if (offset < 0) {
      throw RangeError.value(offset, 'offset', 'Must not be negative.');
    }

    final payload = await _loadJson(
      listPath,
      queryParameters: <String, dynamic>{'limit': limit, 'offset': offset},
    );
    if (payload is! Map) {
      throw const FormatException(
        'Session list response must be a JSON object.',
      );
    }
    final sessions = payload['sessions'];
    if (sessions is! List) {
      throw const FormatException(
        'Session list response must contain a sessions array.',
      );
    }

    final result = <SessionSummary>[];
    for (final item in sessions) {
      if (item is! Map) {
        throw const FormatException('Session list contains an invalid item.');
      }
      result.add(
        SessionSummary.fromJson(
          item.map((key, value) => MapEntry(key.toString(), value)),
        ),
      );
    }
    return List<SessionSummary>.unmodifiable(result);
  }

  Future<SessionDetail> getSession(String id) async {
    final payload = await _loadJson('$listPath/${_sessionId(id)}');
    if (payload is! Map) {
      throw const FormatException('Session detail response must be an object.');
    }
    return SessionDetail.fromJson(
      payload.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  Future<SessionSyncPage> syncSessions({
    int cursor = 0,
    int limit = 200,
  }) async {
    if (cursor < 0) throw RangeError.value(cursor, 'cursor');
    if (limit < 1 || limit > 200) {
      throw RangeError.range(limit, 1, 200, 'limit');
    }
    final payload = await _loadJson(
      '$listPath/sync',
      queryParameters: <String, dynamic>{'cursor': cursor, 'limit': limit},
    );
    if (payload is! Map || payload['sessions'] is! Iterable) {
      throw const FormatException('Session sync response is invalid.');
    }
    final sessions = <SessionSummary>[];
    for (final item in payload['sessions'] as Iterable) {
      if (item is! Map) {
        throw const FormatException('Session sync contains an invalid item.');
      }
      sessions.add(
        SessionSummary.fromJson(
          item.map((key, value) => MapEntry(key.toString(), value)),
        ),
      );
    }
    final deleted = payload['deleted_session_ids'];
    return SessionSyncPage(
      cursor: _nonNegativeInt(payload['cursor']),
      sessions: List<SessionSummary>.unmodifiable(sessions),
      deletedSessionIds: List<String>.unmodifiable(
        (deleted is Iterable ? deleted : const <Object>[])
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty),
      ),
      hasMore: payload['has_more'] == true,
      incremental: payload['incremental'] != false,
    );
  }

  Future<void> renameSession(String id, String title) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty || normalizedTitle.length > 100) {
      throw const FormatException('会话标题长度应为 1–100 个字符。');
    }
    await _writer()(
      'PATCH',
      '$listPath/${_sessionId(id)}',
      data: <String, dynamic>{'title': normalizedTitle},
    );
  }

  Future<void> deleteSession(String id) async {
    await _writer()('DELETE', '$listPath/${_sessionId(id)}');
  }

  SessionJsonWriter _writer() {
    final writer = _writeJson;
    if (writer == null) {
      throw UnsupportedError(
        'This SessionApi instance does not support mutation requests.',
      );
    }
    return writer;
  }

  static String _sessionId(String value) {
    final id = value.trim();
    if (id.isEmpty || id.contains('/')) {
      throw const FormatException('会话 ID 无效。');
    }
    return Uri.encodeComponent(id);
  }

  static int _nonNegativeInt(Object? value) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    return parsed < 0 ? 0 : parsed;
  }
}
