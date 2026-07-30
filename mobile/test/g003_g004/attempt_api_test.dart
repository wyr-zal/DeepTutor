import 'dart:convert';
import 'dart:typed_data';

import 'package:deeptutor_mobile/api/api_client.dart';
import 'package:deeptutor_mobile/api/attempt_api.dart';
import 'package:deeptutor_mobile/models/judge_result.dart';
import 'package:deeptutor_mobile/models/quiz_attempt.dart';
import 'package:deeptutor_mobile/models/quiz_question.dart';
import 'package:deeptutor_mobile/services/auth_store.dart';
import 'package:dio/dio.dart';
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

class _AttemptAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.method == 'GET') {
      return _json(<String, Object?>{
        'attempts': <Object?>[
          _attempt.toJson(),
        ],
      });
    }
    if (options.method == 'POST') {
      return _json(<String, Object?>{'saved': true});
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

final _attempt = QuizAttempt.create(
  question: const QuizQuestion(
    id: 'q-1',
    question: '2 + 2 = ?',
    questionType: 'short_answer',
    options: <String, String>{},
    correctAnswer: '4',
    explanation: '加法。',
  ),
  userAnswer: '4',
  result: JudgeResult.fromText('正确', completedAt: DateTime.utc(2026, 7, 29)),
  createdAt: DateTime.utc(2026, 7, 29),
);

void main() {
  test('lists and saves mobile attempts through the fixed server API',
      () async {
    final storage = _MemorySecureStore();
    final adapter = _AttemptAdapter();
    final client = ApiClient(
      authStore: AuthStore(storage),
      dio: Dio()..httpClientAdapter = adapter,
    );
    addTearDown(client.dispose);
    final api = AttemptApi.fromApiClient(
      client,
      baseUrl: 'https://deeptutor.cliproxy.com.cn',
    );

    final attempts = await api.listAttempts(limit: 20);
    await api.saveAttempt(_attempt);

    expect(attempts.single.question.question, '2 + 2 = ?');
    expect(adapter.requests[0].uri.toString(),
        'https://deeptutor.cliproxy.com.cn/api/v1/mobile/attempts?limit=20');
    expect(adapter.requests[1].method, 'POST');
    expect(adapter.requests[1].uri.toString(),
        'https://deeptutor.cliproxy.com.cn/api/v1/mobile/attempts');
  });
}
