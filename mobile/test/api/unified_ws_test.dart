import 'dart:async';
import 'dart:convert';

import 'package:deeptutor_mobile/api/unified_ws.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('parses the unified envelope without flattening metadata', () {
    final event = UnifiedEvent.parse(<String, Object?>{
      'type': 'content',
      'content': '你好',
      'metadata': <String, Object?>{
        'call_kind': 'quiz_question_emitted',
      },
      'session_id': 'session-1',
      'turn_id': 'turn-1',
      'seq': 7,
    });

    expect(event.type, UnifiedEventType.content);
    expect(event.content, '你好');
    expect(event.metadata['call_kind'], 'quiz_question_emitted');
    expect(event.sessionId, 'session-1');
    expect(event.turnId, 'turn-1');
    expect(event.seq, 7);
  });

  test('maps session, result, done, active turn and unknown events', () {
    expect(
      UnifiedEvent.parse(<String, Object?>{'type': 'session'}).type,
      UnifiedEventType.session,
    );
    expect(
      UnifiedEvent.parse(<String, Object?>{'type': 'result'}).type,
      UnifiedEventType.result,
    );
    expect(
      UnifiedEvent.parse(<String, Object?>{'type': 'done'}).type,
      UnifiedEventType.done,
    );
    expect(
      UnifiedEvent.parse(<String, Object?>{'type': 'active_turn_info'}).type,
      UnifiedEventType.activeTurnInfo,
    );
    expect(
      UnifiedEvent.parse(<String, Object?>{'type': 'session_meta'}).type,
      UnifiedEventType.sessionMeta,
    );
    expect(
      UnifiedEvent.parse(<String, Object?>{'type': 'future_event'}).type,
      UnifiedEventType.unknown,
    );
  });

  test('rejects malformed non-object envelopes', () {
    expect(() => UnifiedEvent.parse('[]'), throwsFormatException);
  });

  test('connects to normalized /api/v1/ws and sends start_turn contract',
      () async {
    Uri? connectedUri;
    final channel = _ControlledChannel();
    final client = UnifiedChatClient(
      baseUrl: 'https://example.test/deeptutor/api/v1',
      tokenLoader: () async => 'jwt-token',
      connector: (uri) {
        connectedUri = uri;
        return channel;
      },
      pingInterval: Duration.zero,
    );
    await client.startTurn(
      content: '二次函数',
      capability: 'deep_question',
      knowledgeBases: const <String>['math'],
      sessionId: null,
      config: const <String, Object?>{
        'mode': 'custom',
        'num_questions': 3,
      },
    );

    expect(
      connectedUri.toString(),
      'wss://example.test/deeptutor/api/v1/ws?token=jwt-token',
    );
    final payload = jsonDecode(channel.sent.single as String);
    expect(payload, <String, Object?>{
      'type': 'start_turn',
      'content': '二次函数',
      'capability': 'deep_question',
      'knowledge_bases': <String>['math'],
      'session_id': '',
      'language': 'zh',
      'config': <String, Object?>{
        'mode': 'custom',
        'num_questions': 3,
      },
    });

    await client.dispose();
  });

  test('forwards events and emits resume_from after reconnect state exists',
      () async {
    final channel = _ControlledChannel();
    final client = UnifiedChatClient(
      baseUrl: 'http://127.0.0.1:8001',
      tokenLoader: () async => null,
      connector: (_) => channel,
      pingInterval: Duration.zero,
    );
    final events = <UnifiedEvent>[];
    final subscription = client.events.listen(events.add);

    await client.connect();
    channel.add(<String, Object?>{
      'type': 'session',
      'metadata': <String, Object?>{
        'session_id': 's1',
        'turn_id': 't1',
      },
      'turn_id': 't1',
      'seq': 1,
    });
    channel.add(<String, Object?>{
      'type': 'content',
      'content': '片段',
      'turn_id': 't1',
      'seq': 2,
    });
    await Future<void>.delayed(Duration.zero);

    expect(events.map((event) => event.type), <UnifiedEventType>[
      UnifiedEventType.session,
      UnifiedEventType.content,
    ]);
    await client.resumeFrom(turnId: 't1', seq: 2);
    expect(
      jsonDecode(channel.sent.last as String),
      <String, Object?>{'type': 'resume_from', 'turn_id': 't1', 'seq': 2},
    );

    await client.checkActiveTurn('s1');
    expect(
      jsonDecode(channel.sent.last as String),
      <String, Object?>{'type': 'check_active_turn', 'session_id': 's1'},
    );

    await client.cancelTurn('t1');
    expect(
      jsonDecode(channel.sent.last as String),
      <String, Object?>{'type': 'cancel_turn', 'turn_id': 't1'},
    );

    await subscription.cancel();
    await client.dispose();
  });

  test('bounds reconnects when sockets open and immediately close', () async {
    final channels = <_ControlledChannel>[];
    final errors = <Object>[];
    final client = UnifiedChatClient(
      baseUrl: 'http://127.0.0.1:8001',
      tokenLoader: () async => null,
      connector: (_) {
        final channel = _ControlledChannel();
        channels.add(channel);
        Future<void>.microtask(channel.disconnect);
        return channel;
      },
      pingInterval: Duration.zero,
      maxReconnectAttempts: 1,
    );
    final subscription = client.events.listen(
      (_) {},
      onError: errors.add,
    );

    await client.connect();
    await Future<void>.delayed(const Duration(milliseconds: 2200));

    expect(channels, hasLength(2));
    expect(errors, contains(isA<UnifiedConnectionException>()));

    await subscription.cancel();
    await client.dispose();
  });

  test('manual reconnect replaces a live socket', () async {
    final channels = <_ControlledChannel>[];
    final client = UnifiedChatClient(
      baseUrl: 'http://127.0.0.1:8001',
      tokenLoader: () async => null,
      connector: (_) {
        final channel = _ControlledChannel();
        channels.add(channel);
        return channel;
      },
      pingInterval: Duration.zero,
    );

    await client.connect();
    await client.reconnect();

    expect(channels, hasLength(2));
    expect(channels.first.isClosed, isTrue);
    expect(client.isConnected, isTrue);

    await client.dispose();
  });

  test('cancelled turn is not resumed after a late event and reconnect',
      () async {
    final channels = <_ControlledChannel>[];
    final client = UnifiedChatClient(
      baseUrl: 'http://127.0.0.1:8001',
      tokenLoader: () async => null,
      connector: (_) {
        final channel = _ControlledChannel();
        channels.add(channel);
        return channel;
      },
      pingInterval: Duration.zero,
    );
    final received = <UnifiedEvent>[];
    final subscription = client.events.listen(received.add);

    await client.connect();
    channels.single.add(<String, Object?>{
      'type': 'session',
      'turn_id': 'turn-1',
      'seq': 1,
    });
    await Future<void>.delayed(Duration.zero);
    await client.cancelTurn('turn-1');
    channels.single.add(<String, Object?>{
      'type': 'content',
      'turn_id': 'turn-1',
      'seq': 2,
      'content': 'late',
    });
    await Future<void>.delayed(Duration.zero);

    await client.reconnect();

    expect(channels, hasLength(2));
    expect(
      received.where((event) => event.content == 'late'),
      isEmpty,
    );
    expect(
      channels.last.sent.map((payload) => jsonDecode(payload as String)),
      isNot(contains(<String, Object?>{
        'type': 'resume_from',
        'turn_id': 'turn-1',
        'seq': 2,
      })),
    );

    await subscription.cancel();
    await client.dispose();
  });
}

class _ControlledChannel implements WebSocketChannel {
  final StreamController<Object?> _controller = StreamController<Object?>();
  final Completer<void> _closed = Completer<void>();
  final List<Object?> sent = <Object?>[];

  bool get isClosed => _closed.isCompleted;

  void add(Map<String, Object?> event) => _controller.add(jsonEncode(event));

  Future<void> disconnect() async {
    if (!_controller.isClosed) await _controller.close();
  }

  @override
  Stream get stream => _controller.stream;

  @override
  Future<void> get ready async {}

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  WebSocketSink get sink => _ControlledSink(sent, _controller, _closed);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ControlledSink implements WebSocketSink {
  _ControlledSink(this.sent, this.controller, this.closed);

  final List<Object?> sent;
  final StreamController<Object?> controller;
  final Completer<void> closed;

  @override
  void add(Object? data) => sent.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    controller.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream stream) async {
    await for (final item in stream) {
      add(item);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!closed.isCompleted) closed.complete();
    if (!controller.isClosed) await controller.close();
  }

  @override
  Future<void> get done => closed.future;
}
