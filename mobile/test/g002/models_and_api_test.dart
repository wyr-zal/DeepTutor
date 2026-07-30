import 'dart:async';
import 'dart:convert';

import 'package:deeptutor_mobile/api/knowledge_api.dart';
import 'package:deeptutor_mobile/api/question_ws.dart';
import 'package:deeptutor_mobile/models/knowledge_base.dart';
import 'package:deeptutor_mobile/models/quiz_question.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  group('KnowledgeApi', () {
    test('parses the backend bare-array contract', () async {
      final api = KnowledgeApi(
        loadJson: (path) async {
          expect(path, '/api/v1/knowledge/list');
          return <Object?>[
            <String, Object?>{
              'id': 'user:kb:math',
              'name': 'math',
              'is_default': true,
              'statistics': <String, Object?>{'document_count': 4},
              'read_only': true,
            },
          ];
        },
      );

      final result = await api.listKnowledgeBases();

      expect(result, hasLength(1));
      expect(result.single.name, 'math');
      expect(result.single.documentCount, 4);
      expect(result.single.isDefault, isTrue);
      expect(result.single.readOnly, isTrue);
    });

    test('rejects a wrapped list so contract drift is visible', () async {
      final api = KnowledgeApi(
        loadJson: (_) async => <String, Object?>{'items': <Object?>[]},
      );

      expect(api.listKnowledgeBases, throwsFormatException);
    });
  });

  test('KnowledgeBase rejects missing names', () {
    expect(
      () => KnowledgeBase.fromJson(<String, Object?>{'name': '  '}),
      throwsFormatException,
    );
  });

  group('QuizQuestion', () {
    test('parses the backend qa_pair shape', () {
      final question = QuizQuestion.fromJson(<String, Object?>{
        'question_id': 'q-1',
        'question': '2 + 2 = ?',
        'question_type': 'choice',
        'options': <String, String>{'A': '3', 'B': '4'},
        'correct_answer': '4',
        'explanation': 'Basic addition.',
        'difficulty': 'easy',
      });

      expect(question.id, 'q-1');
      expect(question.questionType, 'choice');
      expect(question.options, <String, String>{'A': '3', 'B': '4'});
      expect(question.correctAnswer, '4');
      expect(question.deduplicationKey, 'id:q-1');
    });

    test('uses stable content deduplication when id is absent', () {
      const first = QuizQuestion(
        id: '',
        question: '  What is Dart? ',
        questionType: 'Concept',
        options: <String, String>{},
        correctAnswer: 'A language',
        explanation: '',
      );
      const second = QuizQuestion(
        id: '',
        question: 'what is dart?',
        questionType: 'concept',
        options: <String, String>{},
        correctAnswer: 'A language',
        explanation: '',
      );

      expect(first.deduplicationKey, second.deduplicationKey);
    });
  });

  test('generation request matches the backend payload exactly', () {
    const request = QuizGenerationRequest(
      knowledgeBaseName: 'math',
      knowledgePoint: 'quadratic functions',
      preference: 'real-world examples',
      difficulty: 'medium',
      questionType: 'choice',
      count: 3,
    );

    expect(request.toJson(), <String, Object?>{
      'requirement': <String, Object?>{
        'knowledge_point': 'quadratic functions',
        'preference': 'real-world examples',
        'difficulty': 'medium',
        'question_type': 'choice',
      },
      'kb_name': 'math',
      'count': 3,
    });
  });

  test('question websocket does not duplicate an existing api prefix',
      () async {
    Uri? connectedUri;
    final channel = _QuestionChannel(<String>[
      jsonEncode(<String, Object?>{'type': 'complete'}),
    ]);
    final client = QuestionWsClient(
      baseUrl: 'https://example.com/deeptutor/api/v1',
      tokenLoader: () async => 'token',
      connector: (uri) {
        connectedUri = uri;
        return channel;
      },
      maxReconnectAttempts: 0,
    );

    final events = await client
        .generate(
          const QuizGenerationRequest(
            knowledgeBaseName: 'math',
            knowledgePoint: 'algebra',
            preference: '',
            difficulty: 'medium',
            questionType: 'choice',
            count: 1,
          ),
        )
        .toList();

    expect(
      connectedUri.toString(),
      'wss://example.com/deeptutor/api/v1/question/generate?token=token',
    );
    expect(events.last.type, QuestionStreamEventType.complete);
  });

  test('question websocket retries only before receiving server events',
      () async {
    var connections = 0;
    final client = QuestionWsClient(
      baseUrl: 'https://example.com',
      tokenLoader: () async => null,
      connector: (_) {
        connections++;
        if (connections == 1) return _QuestionChannel(const <String>[]);
        return _QuestionChannel(<String>[
          jsonEncode(<String, Object?>{'type': 'complete'}),
        ]);
      },
      maxReconnectAttempts: 1,
      retryDelay: Duration.zero,
    );

    final events = await client
        .generate(
          const QuizGenerationRequest(
            knowledgeBaseName: 'math',
            knowledgePoint: 'algebra',
            preference: '',
            difficulty: 'medium',
            questionType: 'choice',
            count: 1,
          ),
        )
        .toList();

    expect(connections, 2);
    expect(
      events.where((event) => event.type == QuestionStreamEventType.connected),
      hasLength(2),
    );
    expect(events.last.type, QuestionStreamEventType.complete);
  });

  test('question websocket skips failed items and keeps later questions',
      () async {
    final channel = _QuestionChannel(<String>[
      jsonEncode(<String, Object?>{
        'type': 'question',
        'success': false,
        'index': 0,
        'error': 'provider unavailable',
      }),
      jsonEncode(<String, Object?>{
        'type': 'question',
        'success': true,
        'index': 1,
        'question': <String, Object?>{
          'question_id': 'q-2',
          'question': '3 + 5 = ?',
          'question_type': 'choice',
          'options': <String, String>{'A': '7', 'B': '8'},
          'correct_answer': '8',
          'explanation': 'Basic addition.',
        },
      }),
      jsonEncode(<String, Object?>{
        'type': 'batch_summary',
        'requested': 2,
        'completed': 1,
        'failed': 1,
      }),
      jsonEncode(<String, Object?>{'type': 'complete'}),
    ]);
    final client = QuestionWsClient(
      baseUrl: 'https://example.com',
      tokenLoader: () async => null,
      connector: (_) => channel,
      maxReconnectAttempts: 0,
    );

    final events = await client
        .generate(
          const QuizGenerationRequest(
            knowledgeBaseName: 'math',
            knowledgePoint: 'arithmetic',
            preference: '',
            difficulty: 'easy',
            questionType: 'choice',
            count: 2,
          ),
        )
        .toList();

    final questions = events
        .where((event) => event.type == QuestionStreamEventType.question)
        .toList();
    final summary = events.singleWhere(
      (event) => event.type == QuestionStreamEventType.batchSummary,
    );
    expect(questions, hasLength(1));
    expect(questions.single.question?.id, 'q-2');
    expect(summary.failed, 1);
    expect(events.last.type, QuestionStreamEventType.complete);
  });

  test('question websocket bounds a stalled handshake and close', () async {
    final client = QuestionWsClient(
      baseUrl: 'https://example.com',
      tokenLoader: () async => null,
      connector: (_) => _QuestionChannel(
        const <String>[],
        ready: Completer<void>().future,
        closeCompletes: false,
      ),
      maxReconnectAttempts: 0,
      connectTimeout: const Duration(milliseconds: 10),
      closeTimeout: const Duration(milliseconds: 10),
      retryDelay: Duration.zero,
    );

    await expectLater(
      client
          .generate(
            const QuizGenerationRequest(
              knowledgeBaseName: 'math',
              knowledgePoint: 'algebra',
              preference: '',
              difficulty: 'medium',
              questionType: 'choice',
              count: 1,
            ),
          )
          .toList(),
      throwsA(
        isA<QuestionConnectionException>().having(
          (error) => error.message,
          'message',
          '连接出题服务超时，请检查网络后重试。',
        ),
      ),
    ).timeout(const Duration(seconds: 1));
  });

  test(
      'question websocket classifies an authenticated 403 handshake as expired',
      () async {
    final client = QuestionWsClient(
      baseUrl: 'https://example.com',
      tokenLoader: () async => 'expired-token',
      connector: (_) => _QuestionChannel(
        const <String>[],
        ready: Future<void>.error(
          WebSocketChannelException(
            'WebSocket connection failed with status code 403',
          ),
        ),
      ),
      maxReconnectAttempts: 2,
      retryDelay: Duration.zero,
    );

    await expectLater(
      client
          .generate(
            const QuizGenerationRequest(
              knowledgeBaseName: 'math',
              knowledgePoint: 'algebra',
              preference: '',
              difficulty: 'medium',
              questionType: 'choice',
              count: 1,
            ),
          )
          .toList(),
      throwsA(isA<QuestionUnauthorizedException>()),
    );
  });
}

class _QuestionChannel implements WebSocketChannel {
  _QuestionChannel(
    List<String> messages, {
    Future<void>? ready,
    this.closeCompletes = true,
  })  : _stream = Stream<String>.fromIterable(messages),
        _ready = ready ?? Future<void>.value();

  final Stream<String> _stream;
  final Future<void> _ready;
  final bool closeCompletes;
  final List<Object?> sent = <Object?>[];
  final Completer<void> _closed = Completer<void>();

  @override
  Stream get stream => _stream;

  @override
  Future<void> get ready => _ready;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  WebSocketSink get sink =>
      _QuestionSink(sent, _closed, closeCompletes: closeCompletes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuestionSink implements WebSocketSink {
  _QuestionSink(
    this.sent,
    this.closed, {
    this.closeCompletes = true,
  });

  final List<Object?> sent;
  final Completer<void> closed;
  final bool closeCompletes;

  @override
  void add(Object? data) => sent.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream stream) async {
    await for (final item in stream) {
      add(item);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (closeCompletes && !closed.isCompleted) closed.complete();
    if (!closeCompletes) await Completer<void>().future;
  }

  @override
  Future<void> get done => closed.future;
}
