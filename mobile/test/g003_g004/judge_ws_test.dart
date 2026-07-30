import 'dart:async';
import 'dart:convert';

import 'package:deeptutor_mobile/api/judge_ws.dart';
import 'package:deeptutor_mobile/models/judge_result.dart';
import 'package:deeptutor_mobile/models/quiz_question.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  const question = QuizQuestion(
    id: 'q1',
    question: '2 + 2 = ?',
    questionType: 'short_answer',
    correctAnswer: '4',
    explanation: '基础加法。',
  );

  test(
    'concatenates started/text/done stream without inventing markers',
    () async {
      final channel = _FakeChannel(
        messages: <String>[
          '{"type":"started"}',
          '{"type":"text","content":"回答"}',
          '{"type":"text","content":"正确。"}',
          '{"type":"done"}',
        ],
      );
      Uri? connectedUri;
      final client = JudgeWsClient(
        endpoint: Uri.parse('wss://example.test/api/v1/question/judge'),
        token: 'jwt-token',
        channelFactory: (uri) {
          connectedUri = uri;
          return channel;
        },
      );

      final events =
          await client.judge(question: question, userAnswer: '4').toList();

      expect(connectedUri?.queryParameters['token'], 'jwt-token');
      expect(events.map((event) => event.type), <JudgeEventType>[
        JudgeEventType.connecting,
        JudgeEventType.started,
        JudgeEventType.text,
        JudgeEventType.text,
        JudgeEventType.done,
      ]);
      expect(events.last.result?.text, '回答正确。');
      expect(events.last.result?.verdict, JudgeVerdict.unknown);

      final sent =
          jsonDecode(channel.sent.single as String) as Map<String, dynamic>;
      expect(sent['question'], question.question);
      expect(sent['user_answer'], '4');
      expect(sent['language'], 'zh');
    },
  );

  test('does not reconnect after a server error event', () async {
    var connections = 0;
    final client = JudgeWsClient(
      endpoint: Uri.parse('wss://example.test/api/v1/question/judge'),
      token: 'jwt-token',
      channelFactory: (_) {
        connections++;
        return _FakeChannel(
          messages: const <String>[
            '{"type":"error","content":"provider unavailable"}',
          ],
        );
      },
      maxReconnectAttempts: 2,
    );

    final events =
        await client.judge(question: question, userAnswer: '4').toList();

    expect(connections, 1);
    expect(events.last.type, JudgeEventType.error);
    expect(events.last.content, 'provider unavailable');
  });

  test('bounds a stalled handshake and close', () async {
    final client = JudgeWsClient(
      endpoint: Uri.parse('wss://example.test/api/v1/question/judge'),
      token: 'jwt-token',
      channelFactory: (_) => _FakeChannel(
        messages: const <String>[],
        ready: Completer<void>().future,
        closeCompletes: false,
      ),
      maxReconnectAttempts: 0,
      connectTimeout: const Duration(milliseconds: 10),
      closeTimeout: const Duration(milliseconds: 10),
    );

    final events = await client
        .judge(question: question, userAnswer: '4')
        .toList()
        .timeout(const Duration(seconds: 1));

    expect(events.last.type, JudgeEventType.error);
    expect(events.last.content, contains('超时'));
  });

  test('classifies an authenticated 403 handshake as expired', () async {
    final client = JudgeWsClient(
      endpoint: Uri.parse('wss://example.test/api/v1/question/judge'),
      token: 'expired-token',
      channelFactory: (_) => _FakeChannel(
        messages: const <String>[],
        ready: Future<void>.error(
          WebSocketChannelException(
            'WebSocket connection failed with status code 403',
          ),
        ),
      ),
      maxReconnectAttempts: 2,
    );

    final events =
        await client.judge(question: question, userAnswer: '4').toList();

    expect(events, hasLength(2));
    expect(events.last.type, JudgeEventType.error);
    expect(events.last.unauthorized, isTrue);
    expect(events.last.content, '登录已失效，请重新登录。');
  });

  test('bounds close when cancelled as the handshake completes', () async {
    final ready = Completer<void>();
    final client = JudgeWsClient(
      endpoint: Uri.parse('wss://example.test/api/v1/question/judge'),
      token: 'jwt-token',
      channelFactory: (_) => _FakeChannel(
        messages: const <String>[],
        ready: ready.future,
        closeCompletes: false,
      ),
      maxReconnectAttempts: 0,
      connectTimeout: const Duration(seconds: 1),
      closeTimeout: const Duration(milliseconds: 10),
    );

    final eventsFuture =
        client.judge(question: question, userAnswer: '4').toList();
    await Future<void>.delayed(Duration.zero);
    await client.cancel().timeout(const Duration(seconds: 1));
    ready.complete();

    final events = await eventsFuture.timeout(const Duration(seconds: 1));
    expect(events.map((event) => event.type), <JudgeEventType>[
      JudgeEventType.connecting,
    ]);
  });
}

class _FakeChannel implements WebSocketChannel {
  _FakeChannel({
    required List<String> messages,
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
      _FakeSink(sent, _closed, closeCompletes: closeCompletes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSink implements WebSocketSink {
  _FakeSink(
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
