import 'package:dio/dio.dart';

import '../config/server_url.dart';
import '../models/session_summary.dart';
import 'api_client.dart';

typedef SessionJsonLoader = Future<Object?> Function(
  String path, {
  Map<String, dynamic>? queryParameters,
});

abstract interface class SessionRepository {
  Future<List<SessionSummary>> listSessions({int limit = 50, int offset = 0});
}

class SessionApi implements SessionRepository {
  SessionApi({required SessionJsonLoader loadJson}) : _loadJson = loadJson;

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
    );
  }

  static const listPath = '/api/v1/sessions';

  final SessionJsonLoader _loadJson;

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
}
