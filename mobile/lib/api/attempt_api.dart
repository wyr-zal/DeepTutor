import '../models/quiz_attempt.dart';
import 'api_client.dart';

abstract interface class AttemptRepository {
  Future<List<QuizAttempt>> listAttempts({int limit = 200});

  Future<void> saveAttempt(QuizAttempt attempt);
}

class AttemptApi implements AttemptRepository {
  AttemptApi({
    required ApiClient client,
    required String baseUrl,
  })  : _client = client,
        _baseUrl = baseUrl;

  factory AttemptApi.fromApiClient(
    ApiClient client, {
    required String baseUrl,
  }) {
    return AttemptApi(client: client, baseUrl: baseUrl);
  }

  static const path = '/api/v1/mobile/attempts';

  final ApiClient _client;
  final String _baseUrl;

  @override
  Future<List<QuizAttempt>> listAttempts({int limit = 200}) async {
    if (limit < 1 || limit > 500) {
      throw RangeError.range(limit, 1, 500, 'limit');
    }
    final response = await _client.get<Object?>(
      _baseUrl,
      path,
      queryParameters: <String, dynamic>{'limit': limit},
    );
    final payload = response.data;
    if (payload is! Map) {
      throw const FormatException(
        'Attempt list response must be a JSON object.',
      );
    }
    final attempts = payload['attempts'];
    if (attempts is! Iterable) {
      throw const FormatException(
        'Attempt list response must contain an attempts array.',
      );
    }
    return List<QuizAttempt>.unmodifiable(
      attempts.map((item) {
        if (item is! Map) {
          throw const FormatException('Attempt list contains an invalid item.');
        }
        return QuizAttempt.fromJson(
          item.map((key, value) => MapEntry(key.toString(), value)),
        );
      }),
    );
  }

  @override
  Future<void> saveAttempt(QuizAttempt attempt) async {
    await _client.post<Object?>(
      _baseUrl,
      path,
      data: attempt.toJson(),
    );
  }
}
