import 'dart:async';

import 'package:deeptutor_mobile/api/session_api.dart';
import 'package:deeptutor_mobile/api/unified_ws.dart';
import 'package:deeptutor_mobile/features/auth/auth_controller.dart';
import 'package:deeptutor_mobile/features/chat/chat_controller.dart';
import 'package:deeptutor_mobile/features/chat/local_chat_store_provider.dart';
import 'package:deeptutor_mobile/models/auth_session.dart';
import 'package:deeptutor_mobile/models/chat_message.dart';
import 'package:deeptutor_mobile/models/session_summary.dart';
import 'package:deeptutor_mobile/services/local_chat_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stop closes the local turn and ignores late events', () async {
    final client = _FakeUnifiedChatClient();
    final harness = _ChatHarness(client: client);
    addTearDown(harness.dispose);

    final controller = harness.controller;
    await controller.sendChat('解释傅里叶变换');
    client.emit(_event('session', turnId: 'turn-1', sessionId: 'session-1'));
    client.emit(_event('content', turnId: 'turn-1', content: '已生成'));

    await controller.stop();

    final stopped = harness.state;
    expect(client.cancelledTurnIds, <String>['turn-1']);
    expect(stopped.activeTurnId, isNull);
    expect(stopped.isStreaming, isFalse);
    expect(stopped.messages.last.textBuffer, '已生成');

    client.emit(_event('content', turnId: 'turn-1', content: '迟到内容'));
    expect(harness.state.messages.last.textBuffer, '已生成');
  });

  test('loading a running session replays the unseen active turn from zero',
      () async {
    final client = _FakeUnifiedChatClient(
      onCheckActiveTurn: (client, sessionId) {
        client.emit(
          _event(
            'active_turn_info',
            turnId: 'turn-7',
            extra: <String, Object?>{'status': 'running'},
          ),
        );
      },
    );
    final sessionApi = SessionApi(
      loadJson: (path, {queryParameters}) async => <String, Object?>{
        'session_id': 'session-7',
        'title': '运行中的会话',
        'messages': <Object?>[
          <String, Object?>{
            'id': 1,
            'role': 'user',
            'content': '继续讲解',
            'capability': 'chat',
          },
        ],
        'active_turns': <Object?>[
          <String, Object?>{
            'turn_id': 'turn-7',
            'last_seq': 12,
          },
        ],
      },
    );
    final harness = _ChatHarness(client: client, sessionApi: sessionApi);
    addTearDown(harness.dispose);

    await harness.controller.loadSession('session-7');

    expect(client.checkedSessionIds, <String>['session-7']);
    expect(client.resumeRequests, <(String, int)>[('turn-7', 0)]);
    expect(harness.state.activeTurnId, 'turn-7');
    expect(harness.state.lastSeq, 0);
    expect(harness.state.isStreaming, isTrue);
    expect(harness.state.isLoadingSession, isFalse);
  });

  test('switching sessions preserves and replays a running turn', () async {
    final client = _FakeUnifiedChatClient(
      onCheckActiveTurn: (client, sessionId) {
        if (sessionId == 'session-1') {
          client.emit(
            _event(
              'active_turn_info',
              turnId: 'turn-1',
              extra: <String, Object?>{'status': 'running'},
            ),
          );
        }
      },
    );
    final localStore = _FakeLocalChatStore(
      conversations: <String, LocalConversation>{
        'session-2': const LocalConversation(
          sessionId: 'session-2',
          title: '另一条聊天记录',
          detailRevision: 0,
          messages: <ChatMessage>[
            ChatMessage(
              id: 'assistant-2',
              role: ChatRole.assistant,
              textBuffer: '已保存的内容',
            ),
          ],
        ),
      },
      summaries: <String, SessionSummary>{
        'session-2': _summary(
          id: 'session-2',
          title: '另一条聊天记录',
          messageCount: 1,
          revision: 0,
        ),
      },
    );
    final harness = _ChatHarness(
      client: client,
      localStore: localStore,
      sessionApi: SessionApi(
        loadJson: (path, {queryParameters}) async {
          expect(path, '/api/v1/sessions/session-1');
          return <String, Object?>{
            'session_id': 'session-1',
            'title': '正在出题',
            'messages': const <Object?>[],
            'active_turns': <Object?>[
              <String, Object?>{'turn_id': 'turn-1', 'last_seq': 0},
            ],
          };
        },
      ),
    );
    addTearDown(harness.dispose);

    await harness.controller.sendChat('请出两道题');
    client.emit(_event('session', turnId: 'turn-1', sessionId: 'session-1'));

    // This mirrors the local snapshot persisted before the user navigates
    // away. A running summary makes the return path ask the server for the
    // active turn and replay it from sequence zero.
    await localStore.writeConversation(
      sessionId: 'session-1',
      title: '正在出题',
      messages: harness.state.messages,
      detailRevision: 0,
    );

    await harness.controller.loadSession('session-2');

    expect(client.cancelledTurnIds, isEmpty);
    expect(harness.state.sessionId, 'session-2');
    expect(harness.state.activeTurnId, isNull);
    expect(harness.state.isStreaming, isFalse);

    await harness.controller.loadSession('session-1');

    expect(client.checkedSessionIds, <String>['session-1']);
    expect(client.resumeRequests, <(String, int)>[('turn-1', 0)]);
    expect(harness.state.activeTurnId, 'turn-1');
    expect(harness.state.isStreaming, isTrue);
  });

  test('loading a current cached session avoids fetching remote detail',
      () async {
    final client = _FakeUnifiedChatClient();
    var remoteRequested = false;
    final localStore = _FakeLocalChatStore(
      summaries: <String, SessionSummary>{
        'session-9': _summary(
          id: 'session-9',
          title: '本地会话',
          messageCount: 2,
          revision: 4,
        ),
      },
      conversations: <String, LocalConversation>{
        'session-9': const LocalConversation(
          sessionId: 'session-9',
          title: '本地会话',
          detailRevision: 4,
          messages: <ChatMessage>[
            ChatMessage(
              id: 'user-9',
              role: ChatRole.user,
              textBuffer: '讲一下导数',
            ),
            ChatMessage(
              id: 'assistant-9',
              role: ChatRole.assistant,
              textBuffer: '导数描述变化率。',
            ),
          ],
        ),
      },
    );
    final harness = _ChatHarness(
      client: client,
      localStore: localStore,
      sessionApi: SessionApi(
        loadJson: (_, {queryParameters}) async {
          remoteRequested = true;
          return const <String, Object?>{};
        },
      ),
    );
    addTearDown(harness.dispose);

    await harness.controller.loadSession('session-9');

    expect(remoteRequested, isFalse);
    expect(client.checkedSessionIds, isEmpty);
    expect(harness.state.sessionId, 'session-9');
    expect(harness.state.sessionTitle, '本地会话');
    expect(harness.state.isLoadingSession, isFalse);
    expect(harness.state.messages.last.textBuffer, '导数描述变化率。');
  });

  test(
      'a revision bump matching the local message count settles locally '
      'without refetching', () async {
    final client = _FakeUnifiedChatClient();
    var remoteRequested = false;
    final localStore = _FakeLocalChatStore(
      summaries: <String, SessionSummary>{
        'session-10': _summary(
          id: 'session-10',
          title: '本地会话',
          messageCount: 2,
          revision: 6,
        ),
      },
      conversations: <String, LocalConversation>{
        'session-10': const LocalConversation(
          sessionId: 'session-10',
          title: '本地会话',
          detailRevision: 4,
          messages: <ChatMessage>[
            ChatMessage(
              id: 'user-10',
              role: ChatRole.user,
              textBuffer: '讲一下积分',
            ),
            ChatMessage(
              id: 'assistant-10',
              role: ChatRole.assistant,
              textBuffer: '积分是求和的极限。',
            ),
          ],
        ),
      },
    );
    final harness = _ChatHarness(
      client: client,
      localStore: localStore,
      sessionApi: SessionApi(
        loadJson: (_, {queryParameters}) async {
          remoteRequested = true;
          return const <String, Object?>{};
        },
      ),
    );
    addTearDown(harness.dispose);

    await harness.controller.loadSession('session-10');
    await Future<void>.delayed(Duration.zero);

    expect(remoteRequested, isFalse);
    expect(localStore.detailRevisionUpdates, <(String, int)>[('session-10', 6)]);
    expect(harness.state.messages.last.textBuffer, '积分是求和的极限。');
  });

  test('remote refresh keeps locally stored answer states and thinking text',
      () async {
    final client = _FakeUnifiedChatClient();
    final localStore = _FakeLocalChatStore(
      summaries: <String, SessionSummary>{
        'session-11': _summary(
          id: 'session-11',
          title: '本地会话',
          messageCount: 3,
          revision: 8,
        ),
      },
      conversations: <String, LocalConversation>{
        'session-11': LocalConversation(
          sessionId: 'session-11',
          title: '本地会话',
          detailRevision: 5,
          messages: <ChatMessage>[
            const ChatMessage(
              id: 'user-11',
              role: ChatRole.user,
              textBuffer: '出题',
            ),
            ChatMessage(
              id: 'assistant-11',
              role: ChatRole.assistant,
              textBuffer: '题目如下。',
              thinkingBuffer: '先规划题型',
              answerStates: const <String, QuizAnswerState>{
                'q1': QuizAnswerState(answer: 'A', judgeText: '正确'),
              },
            ),
          ],
        ),
      },
    );
    final harness = _ChatHarness(
      client: client,
      localStore: localStore,
      sessionApi: SessionApi(
        loadJson: (_, {queryParameters}) async => <String, Object?>{
          'session_id': 'session-11',
          'title': '本地会话',
          'revision': 8,
          'messages': <Object?>[
            <String, Object?>{'id': 1, 'role': 'user', 'content': '出题'},
            <String, Object?>{
              'id': 2,
              'role': 'assistant',
              'content': '题目如下。',
            },
            <String, Object?>{'id': 3, 'role': 'user', 'content': '再来一题'},
          ],
        },
      ),
    );
    addTearDown(harness.dispose);

    await harness.controller.loadSession('session-11');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final messages = harness.state.messages;
    expect(messages, hasLength(3));
    expect(messages[1].thinkingBuffer, '先规划题型');
    expect(messages[1].answerStates['q1']?.answer, 'A');
    expect(messages[2].textBuffer, '再来一题');
  });

  test('thinking events accumulate into the assistant thinking buffer',
      () async {
    final client = _FakeUnifiedChatClient();
    final harness = _ChatHarness(client: client);
    addTearDown(harness.dispose);

    final controller = harness.controller;
    await controller.sendChat('解释傅里叶变换');
    client.emit(_event('session', turnId: 'turn-1', sessionId: 'session-1'));
    client.emit(_event('thinking', turnId: 'turn-1', content: '先分析'));
    client.emit(_event('thinking', turnId: 'turn-1', content: '问题结构'));

    final assistant = harness.state.messages.last;
    expect(assistant.thinkingBuffer, '先分析问题结构');
    expect(assistant.thinkingClosed, isFalse);
    // No user-facing content yet, so the body stays empty.
    expect(assistant.textBuffer, '');
  });

  test('first content closes the thinking phase without dropping thinking text',
      () async {
    final client = _FakeUnifiedChatClient();
    final harness = _ChatHarness(client: client);
    addTearDown(harness.dispose);

    final controller = harness.controller;
    await controller.sendChat('解释傅里叶变换');
    client.emit(_event('session', turnId: 'turn-1', sessionId: 'session-1'));
    client.emit(_event('thinking', turnId: 'turn-1', content: '推理中'));

    expect(harness.state.messages.last.thinkingClosed, isFalse);

    client.emit(_event('content', turnId: 'turn-1', content: '傅里叶变换是'));

    final afterContent = harness.state.messages.last;
    expect(afterContent.thinkingBuffer, '推理中');
    expect(afterContent.thinkingClosed, isTrue);
    expect(afterContent.textBuffer, '傅里叶变换是');
  });

  test('done marks thinking closed even when no content event arrives',
      () async {
    final client = _FakeUnifiedChatClient();
    final harness = _ChatHarness(client: client);
    addTearDown(harness.dispose);

    final controller = harness.controller;
    await controller.sendChat('解释傅里叶变换');
    client.emit(_event('session', turnId: 'turn-1', sessionId: 'session-1'));
    client.emit(_event('thinking', turnId: 'turn-1', content: '只思考不作答'));
    client.emit(_event('done', turnId: 'turn-1'));

    final finished = harness.state.messages.last;
    expect(finished.thinkingBuffer, '只思考不作答');
    expect(finished.thinkingClosed, isTrue);
    expect(finished.streaming, isFalse);
    expect(harness.state.isStreaming, isFalse);
  });
}

class _ChatHarness {
  _ChatHarness({
    required _FakeUnifiedChatClient client,
    SessionApi? sessionApi,
    _FakeLocalChatStore? localStore,
  }) : container = ProviderContainer(
          overrides: <Override>[
            authControllerProvider.overrideWith(
              () => _TestAuthController(_session),
            ),
            chatClientFactoryProvider.overrideWithValue((_) => client),
            chatSessionApiFactoryProvider.overrideWithValue(
              (_) =>
                  sessionApi ??
                  SessionApi(
                    loadJson: (_, {queryParameters}) async =>
                        const <String, Object?>{},
                  ),
            ),
            localChatStoreProvider.overrideWith(
              (_, __) => localStore ?? _FakeLocalChatStore(),
            ),
          ],
        ) {
    subscription = container.listen<ChatState>(
      chatControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
  }

  static const _session = AuthSession(
    baseUrl: 'https://tutor.example.com',
    accessToken: 'token',
    tokenType: 'bearer',
    expiresIn: 3600,
    user: AuthUser(
      id: 'user-1',
      username: 'learner',
      role: 'user',
      isAdmin: false,
    ),
    authEnabled: true,
  );

  final ProviderContainer container;
  late final ProviderSubscription<ChatState> subscription;

  ChatController get controller =>
      container.read(chatControllerProvider.notifier);
  ChatState get state => container.read(chatControllerProvider);

  void dispose() {
    subscription.close();
    container.dispose();
  }
}

class _FakeLocalChatStore extends LocalChatStore {
  _FakeLocalChatStore({
    Map<String, LocalConversation>? conversations,
    Map<String, SessionSummary>? summaries,
  })  : conversations = Map<String, LocalConversation>.from(
          conversations ?? const <String, LocalConversation>{},
        ),
        summaries = Map<String, SessionSummary>.from(
          summaries ?? const <String, SessionSummary>{},
        ),
        super(namespace: 'chat_controller_test');

  final Map<String, LocalConversation> conversations;
  final Map<String, SessionSummary> summaries;
  final List<(String, int)> detailRevisionUpdates = <(String, int)>[];
  int cursor = 0;

  @override
  Future<int> readCursor() async => cursor;

  @override
  Future<List<SessionSummary>> readSummaries() async =>
      summaries.values.toList(growable: false);

  @override
  Future<SessionSummary?> readSummary(String sessionId) async =>
      summaries[sessionId];

  @override
  Future<LocalConversation?> readConversation(String sessionId) async =>
      conversations[sessionId];

  @override
  Future<void> updateDetailRevision(String sessionId, int revision) async {
    detailRevisionUpdates.add((sessionId, revision));
    final current = conversations[sessionId];
    if (current != null) {
      conversations[sessionId] = LocalConversation(
        sessionId: current.sessionId,
        title: current.title,
        messages: current.messages,
        detailRevision: revision,
      );
    }
  }

  @override
  Future<void> applySync(SessionSyncPage page) async {
    cursor = page.cursor;
    for (final id in page.deletedSessionIds) {
      summaries.remove(id);
      conversations.remove(id);
    }
    for (final session in page.sessions) {
      summaries[session.id] = session;
    }
  }

  @override
  Future<void> writeConversation({
    required String sessionId,
    required String title,
    required List<ChatMessage> messages,
    required int detailRevision,
  }) async {
    conversations[sessionId] = LocalConversation(
      sessionId: sessionId,
      title: title,
      messages: List<ChatMessage>.unmodifiable(messages),
      detailRevision: detailRevision,
    );
    final current = summaries[sessionId];
    summaries[sessionId] = _summary(
      id: sessionId,
      title: title,
      messageCount: messages.length,
      revision: current?.revision ?? 0,
      status: messages.any((message) => message.streaming) ? 'running' : 'idle',
      lastMessage: messages.reversed
          .map((message) => message.textBuffer.trim())
          .firstWhere((text) => text.isNotEmpty, orElse: () => ''),
    );
  }

  @override
  Future<void> deleteConversation(String sessionId) async {
    summaries.remove(sessionId);
    conversations.remove(sessionId);
  }

  @override
  Future<void> close() async {}
}

SessionSummary _summary({
  required String id,
  required String title,
  required int messageCount,
  required int revision,
  String status = 'idle',
  String lastMessage = '',
}) {
  return SessionSummary(
    id: id,
    title: title,
    capability: 'chat',
    status: status,
    messageCount: messageCount,
    lastMessage: lastMessage,
    createdAt: null,
    updatedAt: null,
    revision: revision,
  );
}

class _TestAuthController extends AuthController {
  _TestAuthController(this.session);

  final AuthSession session;

  @override
  AuthSession? build() => session;
}

typedef _CheckActiveTurnCallback = void Function(
  _FakeUnifiedChatClient client,
  String sessionId,
);

class _FakeUnifiedChatClient extends UnifiedChatClient {
  _FakeUnifiedChatClient({this.onCheckActiveTurn})
      : super(
          baseUrl: 'https://tutor.example.com',
          tokenLoader: () async => 'token',
          pingInterval: Duration.zero,
        );

  final _events = StreamController<UnifiedEvent>.broadcast(sync: true);
  final _CheckActiveTurnCallback? onCheckActiveTurn;
  final List<String> cancelledTurnIds = <String>[];
  final List<String> checkedSessionIds = <String>[];
  final List<(String, int)> resumeRequests = <(String, int)>[];

  @override
  Stream<UnifiedEvent> get events => _events.stream;

  void emit(UnifiedEvent event) => _events.add(event);

  @override
  Future<void> connect() async {}

  @override
  Future<void> startTurn({
    required String content,
    String capability = 'chat',
    List<String> knowledgeBases = const <String>[],
    String? sessionId,
    Map<String, dynamic>? config,
    String language = 'zh',
  }) async {}

  @override
  Future<void> cancelTurn(String turnId) async {
    cancelledTurnIds.add(turnId);
  }

  @override
  Future<void> checkActiveTurn(String sessionId) async {
    checkedSessionIds.add(sessionId);
    onCheckActiveTurn?.call(this, sessionId);
  }

  @override
  Future<void> resumeFrom({required String turnId, required int seq}) async {
    resumeRequests.add((turnId, seq));
  }

  @override
  Future<void> dispose() => _events.close();
}

UnifiedEvent _event(
  String type, {
  String content = '',
  String? turnId,
  String? sessionId,
  Map<String, Object?> extra = const <String, Object?>{},
}) {
  return UnifiedEvent.parse(<String, Object?>{
    'type': type,
    'content': content,
    if (turnId != null) 'turn_id': turnId,
    if (sessionId != null) 'session_id': sessionId,
    ...extra,
  });
}
