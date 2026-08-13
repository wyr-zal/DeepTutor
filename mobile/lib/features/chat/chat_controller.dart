import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/session_api.dart';
import '../../api/unified_ws.dart';
import '../../models/auth_session.dart';
import '../../models/chat_message.dart';
import '../../models/deep_question_config.dart';
import '../../models/quiz_extract.dart';
import '../../models/quiz_question.dart';
import '../../models/session_detail.dart';
import '../../services/local_chat_store.dart';
import '../auth/auth_controller.dart';
import 'local_chat_store_provider.dart';
import 'session_list_controller.dart';

class ChatState {
  const ChatState({
    this.messages = const <ChatMessage>[],
    this.sessionId,
    this.sessionTitle,
    this.activeTurnId,
    this.lastSeq = 0,
    this.isStreaming = false,
    this.isLoadingSession = false,
    this.error,
  });

  final List<ChatMessage> messages;
  final String? sessionId;
  final String? sessionTitle;
  final String? activeTurnId;
  final int lastSeq;
  final bool isStreaming;
  final bool isLoadingSession;
  final String? error;

  ChatState copyWith({
    List<ChatMessage>? messages,
    String? sessionId,
    bool clearSessionId = false,
    String? sessionTitle,
    bool clearSessionTitle = false,
    String? activeTurnId,
    bool clearActiveTurnId = false,
    int? lastSeq,
    bool? isStreaming,
    bool? isLoadingSession,
    String? error,
    bool clearError = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      sessionId: clearSessionId ? null : sessionId ?? this.sessionId,
      sessionTitle:
          clearSessionTitle ? null : sessionTitle ?? this.sessionTitle,
      activeTurnId:
          clearActiveTurnId ? null : activeTurnId ?? this.activeTurnId,
      lastSeq: lastSeq ?? this.lastSeq,
      isStreaming: isStreaming ?? this.isStreaming,
      isLoadingSession: isLoadingSession ?? this.isLoadingSession,
      error: clearError ? null : error ?? this.error,
    );
  }
}

final chatControllerProvider =
    AutoDisposeNotifierProvider<ChatController, ChatState>(ChatController.new);

typedef ChatClientFactory = UnifiedChatClient Function(AuthSession session);
typedef ChatSessionApiFactory = SessionApi Function(AuthSession session);

final chatClientFactoryProvider = Provider<ChatClientFactory>(
  (_) => (session) => UnifiedChatClient(
        baseUrl: session.baseUrl,
        tokenLoader: () async => session.accessToken,
      ),
);

final chatSessionApiFactoryProvider = Provider<ChatSessionApiFactory>((ref) {
  final client = ref.watch(apiClientProvider);
  return (session) => SessionApi.fromApiClient(
        client,
        baseUrl: session.baseUrl,
      );
});

class ChatController extends AutoDisposeNotifier<ChatState> {
  late final UnifiedChatClient _client;
  late final SessionApi _sessionApi;
  late final LocalChatStore _localStore;
  StreamSubscription<UnifiedEvent>? _subscription;
  Timer? _activeTurnCheckTimer;
  Timer? _persistTimer;
  String? _pendingActiveTurnSessionId;
  var _messageSequence = 0;
  final Map<String, int> _streamingQuestionIndexes = <String, int>{};

  @override
  ChatState build() {
    final session = ref.watch(authControllerProvider).requireValue!;
    _sessionApi = ref.read(chatSessionApiFactoryProvider)(session);
    _localStore = ref.read(localChatStoreProvider(session));
    _client = ref.read(chatClientFactoryProvider)(session);
    _subscription = _client.events.listen(
      _onEvent,
      onError: _onStreamError,
    );
    unawaited(_connect());
    ref.onDispose(() {
      _activeTurnCheckTimer?.cancel();
      _persistTimer?.cancel();
      _persistNow();
      unawaited(_subscription?.cancel());
      unawaited(_client.dispose());
    });
    return const ChatState();
  }

  Future<void> _connect() async {
    try {
      await _client.connect();
    } on UnifiedUnauthorized {
      await ref.read(authControllerProvider.notifier).logout();
    } on UnifiedConnectionException catch (error) {
      state = state.copyWith(error: error.message);
    }
  }

  Future<void> reconnect() async {
    state = state.copyWith(clearError: true);
    try {
      await _client.reconnect();
    } on UnifiedUnauthorized {
      await ref.read(authControllerProvider.notifier).logout();
    } on UnifiedConnectionException catch (error) {
      state = state.copyWith(error: error.message);
    }
  }

  Future<void> sendChat(String text) async {
    await _send(
      text: text,
      capability: ChatCapability.chat,
      capabilityName: 'chat',
    );
  }

  Future<void> sendQuiz(
    String topic,
    DeepQuestionFormConfig config,
    List<String> knowledgeBases,
  ) async {
    if (config.mode == DeepQuestionMode.mimic &&
        config.paperPath.trim().isEmpty) {
      state = state.copyWith(error: '请先填写服务器上的试卷目录名。');
      return;
    }
    await _send(
      text: topic,
      capability: ChatCapability.deepQuestion,
      capabilityName: 'deep_question',
      knowledgeBases: knowledgeBases,
      config: buildQuizConfig(config),
    );
  }

  Future<void> _send({
    required String text,
    required ChatCapability capability,
    required String capabilityName,
    List<String> knowledgeBases = const <String>[],
    Map<String, dynamic>? config,
  }) async {
    final content = text.trim();
    if (content.isEmpty || state.isStreaming || state.isLoadingSession) return;

    final userMessage = ChatMessage(
      id: _nextMessageId('user'),
      role: ChatRole.user,
      textBuffer: content,
      capability: capability,
    );
    final assistantMessage = ChatMessage(
      id: _nextMessageId('assistant'),
      role: ChatRole.assistant,
      textBuffer: '',
      capability: capability,
      streaming: true,
    );
    state = state.copyWith(
      messages: <ChatMessage>[
        ...state.messages,
        userMessage,
        assistantMessage,
      ],
      isStreaming: true,
      clearError: true,
      lastSeq: 0,
    );
    _schedulePersist();
    _streamingQuestionIndexes.clear();
    try {
      await _client.startTurn(
        content: content,
        capability: capabilityName,
        knowledgeBases: knowledgeBases,
        sessionId: state.sessionId,
        config: config,
      );
    } on UnifiedUnauthorized {
      _finishCurrentAssistant(error: '登录已失效，请重新登录。');
      await ref.read(authControllerProvider.notifier).logout();
    } on UnifiedConnectionException catch (error) {
      _finishCurrentAssistant(error: error.message);
    } catch (_) {
      _finishCurrentAssistant(error: '消息发送失败，请检查网络后重试。');
    }
  }

  Future<void> stop() async {
    final turnId = state.activeTurnId;
    if (turnId == null || !await _cancelTurn(turnId)) return;
    if (state.activeTurnId == turnId) _finishCurrentAssistant();
  }

  Future<void> newSession() async {
    await _persistConversation();
    // Creating or navigating to another conversation must not terminate an
    // in-flight server turn. The user can still explicitly stop it from the
    // conversation where it was started; returning here will reconcile and
    // replay the active turn from the server.
    _streamingQuestionIndexes.clear();
    _clearActiveTurnCheck();
    state = const ChatState();
  }

  Future<void> loadSession(String id) async {
    if (state.isLoadingSession || id == state.sessionId) return;
    await _persistConversation();
    // Session navigation is not an instruction to cancel the active turn.
    // Clear this view's turn state so background events are ignored until the
    // user returns, then check_active_turn/resume_from restores it.
    _clearActiveTurnCheck();
    state = state.copyWith(
      isLoadingSession: true,
      isStreaming: false,
      clearActiveTurnId: true,
      clearError: true,
    );
    final local = await _localStore.readConversation(id);
    final summary = await _localStore.readSummary(id);
    if (local != null) {
      _streamingQuestionIndexes.clear();
      state = ChatState(
        messages: local.messages,
        sessionId: local.sessionId,
        sessionTitle: local.title,
      );
      if ((summary?.revision ?? -1) > local.detailRevision) {
        // A revision bump caused only by this device's own completed turn:
        // the local copy already holds every message, so just settle the
        // revision instead of refetching the whole session.
        if (summary != null &&
            summary.status != 'running' &&
            summary.messageCount == local.messages.length) {
          unawaited(
            _localStore
                .updateDetailRevision(local.sessionId, summary.revision)
                .catchError((_) {}),
          );
        } else {
          unawaited(_loadRemoteSession(id, preserveLocalOnError: true));
        }
      } else if (summary?.status == 'running') {
        state = state.copyWith(isLoadingSession: true);
        unawaited(_checkActiveTurnForLoadedSession(local.sessionId));
      }
      return;
    }

    await _loadRemoteSession(id, preserveLocalOnError: false);
  }

  Future<void> _loadRemoteSession(
    String id, {
    required bool preserveLocalOnError,
  }) async {
    late final SessionDetail detail;
    try {
      detail = await _sessionApi.getSession(id);
    } on Object {
      state = state.copyWith(
        isLoadingSession: false,
        error:
            preserveLocalOnError ? '本地聊天记录已显示，但远端更新失败。' : '无法加载该会话，请检查网络后重试。',
      );
      return;
    }
    final messages = _mergeLocalDetails(
      _rebuildMessages(detail),
      (await _localStore.readConversation(detail.sessionId))?.messages,
    );
    final summary = await _localStore.readSummary(detail.sessionId);
    final detailRevision = detail.revision ?? summary?.revision ?? 0;
    _streamingQuestionIndexes.clear();
    state = ChatState(
      messages: messages,
      sessionId: detail.sessionId,
      sessionTitle: detail.title,
      isLoadingSession: true,
    );
    await _localStore.writeConversation(
      sessionId: detail.sessionId,
      title: detail.title,
      messages: messages,
      detailRevision: detailRevision,
    );
    await _checkActiveTurnForLoadedSession(detail.sessionId);
  }

  Future<void> _checkActiveTurnForLoadedSession(String sessionId) async {
    _pendingActiveTurnSessionId = sessionId;
    _activeTurnCheckTimer?.cancel();
    _activeTurnCheckTimer = Timer(const Duration(seconds: 10), () {
      if (_pendingActiveTurnSessionId != sessionId ||
          state.sessionId != sessionId) {
        return;
      }
      _clearActiveTurnCheck();
      state = state.copyWith(
        isLoadingSession: false,
        error: '会话已加载，但检查进行中任务超时；可以重试加载该会话。',
      );
    });
    try {
      await _client.checkActiveTurn(sessionId);
    } on UnifiedUnauthorized {
      _clearActiveTurnCheck();
      await ref.read(authControllerProvider.notifier).logout();
    } on UnifiedConnectionException catch (error) {
      _clearActiveTurnCheck();
      state = state.copyWith(
        isLoadingSession: false,
        error: '会话已加载，但${error.message}',
      );
    }
  }

  void _onEvent(UnifiedEvent event) {
    if (_isStaleTurnEvent(event)) return;
    final nextSeq = max(state.lastSeq, event.seq);
    if (nextSeq != state.lastSeq) state = state.copyWith(lastSeq: nextSeq);
    var shouldPersist = false;
    var persistImmediately = false;

    switch (event.type) {
      case UnifiedEventType.session:
        final sessionId = _eventValue(event, 'session_id');
        final turnId = _eventValue(event, 'turn_id');
        state = state.copyWith(
          sessionId: sessionId,
          activeTurnId: turnId,
          clearError: true,
        );
        shouldPersist = true;
        break;
      case UnifiedEventType.content:
        if (event.metadata['call_kind'] == 'quiz_question_emitted') {
          _applyStreamingQuiz(event.metadata);
        } else {
          _updateCurrentAssistant(
            (message) => message.copyWith(
              textBuffer: '${message.textBuffer}${event.content}',
              // First user-facing content closes any open thinking phase.
              thinkingClosed: message.thinkingBuffer.isEmpty
                  ? message.thinkingClosed
                  : true,
            ),
          );
        }
        shouldPersist = true;
        break;
      case UnifiedEventType.result:
        _applyResult(event.metadata);
        shouldPersist = true;
        break;
      case UnifiedEventType.error:
        _updateCurrentAssistant(
          (message) => message.copyWith(error: event.content),
        );
        if (event.metadata['turn_terminal'] == true) {
          _finishCurrentAssistant(error: event.content);
          persistImmediately = true;
        } else {
          state = state.copyWith(error: event.content);
        }
        shouldPersist = true;
        break;
      case UnifiedEventType.done:
        _finishCurrentAssistant();
        shouldPersist = true;
        persistImmediately = true;
        ref.invalidate(sessionListControllerProvider);
        break;
      case UnifiedEventType.sessionMeta:
        final title = _eventValue(event, 'title');
        if (title != null) {
          state = state.copyWith(sessionTitle: title);
          shouldPersist = true;
        }
        ref.invalidate(sessionListControllerProvider);
        break;
      case UnifiedEventType.activeTurnInfo:
        final pendingSessionId = _pendingActiveTurnSessionId;
        if (pendingSessionId == null || pendingSessionId != state.sessionId) {
          break;
        }
        final turnId = event.turnId ?? _eventValue(event, 'turn_id');
        if (turnId == null || event.raw['status'] == 'none') {
          _clearActiveTurnCheck();
          state = state.copyWith(
            isStreaming: false,
            isLoadingSession: false,
            clearActiveTurnId: true,
          );
          shouldPersist = true;
        } else {
          _clearActiveTurnCheck();
          state = state.copyWith(
            activeTurnId: turnId,
            // A newly loaded session has not rendered this active turn yet.
            // Its assistant row/events are persisted only after completion,
            // so replaying from zero is required to avoid dropping content.
            lastSeq: 0,
            isStreaming: true,
            isLoadingSession: false,
          );
          _ensureStreamingAssistant();
          unawaited(_resumeFrom(turnId));
          shouldPersist = true;
        }
        break;
      case UnifiedEventType.thinking:
        final chunk = event.content;
        if (chunk.isNotEmpty) {
          _updateCurrentAssistant(
            (message) => message.copyWith(
              thinkingBuffer: '${message.thinkingBuffer}$chunk',
              thinkingClosed: false,
            ),
          );
          shouldPersist = true;
        }
        break;
      case UnifiedEventType.toolResult:
        if (event.metadata['tool'] == 'ask_user') {
          final askUser = _askUserFromToolMetadata(event.metadata);
          if (askUser != null) {
            _updateCurrentAssistant(
              (message) => message.copyWith(
                askUser: askUser,
                askUserToolCallId:
                    event.metadata['tool_call_id']?.toString() ?? '',
                thinkingClosed: true,
              ),
            );
            shouldPersist = true;
            persistImmediately = true;
          }
        }
        break;
      case UnifiedEventType.progress:
        if (event.metadata['ask_user_resolved'] == true) {
          _resolveAskUser(
            event.metadata['ask_user_tool_call_id']?.toString(),
          );
          shouldPersist = true;
          persistImmediately = true;
        }
        break;
      case UnifiedEventType.stageStart:
      case UnifiedEventType.stageEnd:
      case UnifiedEventType.observation:
      case UnifiedEventType.toolCall:
      case UnifiedEventType.sources:
      case UnifiedEventType.waitForInput:
      case UnifiedEventType.pong:
      case UnifiedEventType.unknown:
        break;
    }
    if (shouldPersist) {
      persistImmediately ? _persistNow() : _schedulePersist();
    }
  }

  void _applyStreamingQuiz(Map<String, dynamic> metadata) {
    final question = extractStreamingQuiz(metadata);
    if (question == null) return;
    final index = streamingQuestionIndex(metadata);
    if (index != null) {
      _streamingQuestionIndexes[question.deduplicationKey] = index;
    }
    _updateCurrentAssistant((message) {
      final byKey = <String, QuizQuestion>{
        for (final item in message.quizQuestions) item.deduplicationKey: item,
        question.deduplicationKey: question,
      };
      final ordered = byKey.values.toList()
        ..sort((left, right) {
          final leftIndex =
              _streamingQuestionIndexes[left.deduplicationKey] ?? 1 << 30;
          final rightIndex =
              _streamingQuestionIndexes[right.deduplicationKey] ?? 1 << 30;
          return leftIndex.compareTo(rightIndex);
        });
      return message.copyWith(quizQuestions: ordered);
    });
  }

  void _applyResult(Map<String, dynamic> metadata) {
    final questions = extractQuizFromResult(metadata);
    final response = metadata['response']?.toString() ?? '';
    final summary = metadata['summary'];
    _updateCurrentAssistant(
      (message) => message.copyWith(
        textBuffer: response.trim().isEmpty ? message.textBuffer : response,
        quizQuestions: questions.isEmpty ? message.quizQuestions : questions,
        quizMeta: summary is Map
            ? summary.map((key, value) => MapEntry(key.toString(), value))
            : message.quizMeta,
      ),
    );
    if (questions.isNotEmpty) _streamingQuestionIndexes.clear();
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    if (error is UnifiedUnauthorized) {
      unawaited(ref.read(authControllerProvider.notifier).logout());
      return;
    }
    final message = error is UnifiedConnectionException
        ? error.message
        : '聊天连接发生异常，正在尝试恢复。';
    state = state.copyWith(error: message);
  }

  Future<void> _resumeFrom(String turnId) async {
    try {
      await _client.resumeFrom(turnId: turnId, seq: state.lastSeq);
    } on UnifiedUnauthorized {
      await ref.read(authControllerProvider.notifier).logout();
    } on UnifiedConnectionException catch (error) {
      state = state.copyWith(error: error.message);
    }
  }

  Future<bool> _cancelTurn(String turnId) async {
    try {
      await _client.cancelTurn(turnId);
      return true;
    } on UnifiedUnauthorized {
      await ref.read(authControllerProvider.notifier).logout();
      return false;
    } on UnifiedConnectionException catch (error) {
      state = state.copyWith(error: error.message);
      return false;
    }
  }

  bool _isStaleTurnEvent(UnifiedEvent event) {
    if (event.type == UnifiedEventType.session) {
      final eventTurn = event.turnId ?? _eventValue(event, 'turn_id');
      if (eventTurn == null) return false;
      final activeTurn = state.activeTurnId;
      return activeTurn == null ? !state.isStreaming : eventTurn != activeTurn;
    }
    if (event.type == UnifiedEventType.activeTurnInfo ||
        event.type == UnifiedEventType.pong) {
      return false;
    }
    if (event.type == UnifiedEventType.sessionMeta) {
      final eventSession = _eventValue(event, 'session_id');
      return eventSession != null && eventSession != state.sessionId;
    }
    final eventTurn = event.turnId ?? _eventValue(event, 'turn_id');
    if (eventTurn == null) return false;
    return state.activeTurnId == null || eventTurn != state.activeTurnId;
  }

  void _clearActiveTurnCheck() {
    _activeTurnCheckTimer?.cancel();
    _activeTurnCheckTimer = null;
    _pendingActiveTurnSessionId = null;
  }

  void updateAnswerState(
    String messageId,
    String questionKey,
    QuizAnswerState answerState,
  ) {
    final messages = List<ChatMessage>.from(state.messages);
    final index = messages.indexWhere((message) => message.id == messageId);
    if (index == -1) return;
    final message = messages[index];
    messages[index] = message.copyWith(
      answerStates: <String, QuizAnswerState>{
        ...message.answerStates,
        questionKey: answerState,
      },
    );
    state = state.copyWith(messages: messages);
    _schedulePersist();
  }

  static Map<String, dynamic>? _askUserFromToolMetadata(
    Map<String, dynamic> metadata,
  ) {
    final toolMetadata = metadata['tool_metadata'];
    if (toolMetadata is! Map) return null;
    final askUser = toolMetadata['ask_user'];
    if (askUser is! Map) return null;
    return askUser.map((key, value) => MapEntry(key.toString(), value));
  }

  void _resolveAskUser(String? toolCallId) {
    final messages = List<ChatMessage>.from(state.messages);
    for (var index = messages.length - 1; index >= 0; index--) {
      final message = messages[index];
      if (message.askUser == null || message.askUserResolved) continue;
      if (toolCallId != null &&
          toolCallId.isNotEmpty &&
          message.askUserToolCallId != null &&
          message.askUserToolCallId!.isNotEmpty &&
          message.askUserToolCallId != toolCallId) {
        continue;
      }
      messages[index] = message.copyWith(
        askUserResolved: true,
        askUserSubmitting: false,
      );
      state = state.copyWith(messages: messages);
      return;
    }
  }

  Future<void> submitUserReply(
    String messageId, {
    required String text,
    List<Map<String, String>> answers = const <Map<String, String>>[],
  }) async {
    final turnId = state.activeTurnId;
    if (turnId == null) {
      state = state.copyWith(error: '当前没有等待回答的任务，无法提交。');
      return;
    }
    _setAskUserSubmitting(messageId, true);
    try {
      await _client.submitUserReply(
        turnId: turnId,
        text: text,
        answers: answers,
      );
    } on UnifiedUnauthorized {
      _setAskUserSubmitting(messageId, false);
      await ref.read(authControllerProvider.notifier).logout();
    } on UnifiedConnectionException catch (error) {
      _setAskUserSubmitting(messageId, false);
      state = state.copyWith(error: error.message);
    } catch (_) {
      _setAskUserSubmitting(messageId, false);
      state = state.copyWith(error: '回答提交失败，请检查网络后重试。');
    }
  }

  void _setAskUserSubmitting(String messageId, bool submitting) {
    final messages = List<ChatMessage>.from(state.messages);
    final index = messages.indexWhere((message) => message.id == messageId);
    if (index == -1) return;
    messages[index] = messages[index].copyWith(askUserSubmitting: submitting);
    state = state.copyWith(messages: messages);
  }

  void _finishCurrentAssistant({String? error}) {
    _updateCurrentAssistant(
      (message) => message.copyWith(
        streaming: false,
        error: error,
        clearError: error == null,
        // The turn is over; any thinking phase is definitively closed.
        thinkingClosed: true,
      ),
    );
    state = state.copyWith(
      isStreaming: false,
      clearActiveTurnId: true,
      error: error,
      clearError: error == null,
    );
    _schedulePersist();
  }

  void _ensureStreamingAssistant() {
    if (state.messages.isNotEmpty &&
        state.messages.last.role == ChatRole.assistant &&
        state.messages.last.streaming) {
      return;
    }
    state = state.copyWith(
      messages: <ChatMessage>[
        ...state.messages,
        ChatMessage(
          id: _nextMessageId('assistant'),
          role: ChatRole.assistant,
          textBuffer: '',
          streaming: true,
        ),
      ],
    );
    _schedulePersist();
  }

  void _updateCurrentAssistant(
    ChatMessage Function(ChatMessage message) update,
  ) {
    final messages = List<ChatMessage>.from(state.messages);
    for (var index = messages.length - 1; index >= 0; index--) {
      if (messages[index].role != ChatRole.assistant) continue;
      messages[index] = update(messages[index]);
      state = state.copyWith(messages: messages);
      return;
    }
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 350), _persistNow);
  }

  void _persistNow() {
    _persistTimer?.cancel();
    _persistTimer = null;
    unawaited(_persistConversation().catchError((_) {}));
  }

  Future<void> _persistConversation() async {
    final sessionId = state.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty || state.messages.isEmpty) {
      return;
    }
    final summary = await _localStore.readSummary(sessionId);
    final local = await _localStore.readConversation(sessionId);
    final title = (state.sessionTitle ?? local?.title ?? '').trim();
    await _localStore.writeConversation(
      sessionId: sessionId,
      title: title.isEmpty ? '未命名会话' : title,
      messages: state.messages,
      detailRevision: summary?.revision ?? local?.detailRevision ?? -1,
    );
  }

  /// Server rebuilds only carry role/content/quiz; graft locally-only fields
  /// (answer states, thinking text) back on, aligned by position + role since
  /// server message ids differ from locally generated ones.
  static List<ChatMessage> _mergeLocalDetails(
    List<ChatMessage> remote,
    List<ChatMessage>? local,
  ) {
    if (local == null || local.isEmpty) return remote;
    return List<ChatMessage>.unmodifiable(
      List<ChatMessage>.generate(remote.length, (index) {
        final message = remote[index];
        if (index >= local.length || local[index].role != message.role) {
          return message;
        }
        final source = local[index];
        return message.copyWith(
          answerStates:
              source.answerStates.isEmpty ? null : source.answerStates,
          thinkingBuffer:
              source.thinkingBuffer.isEmpty ? null : source.thinkingBuffer,
          thinkingClosed: true,
          quizMeta: message.quizMeta ?? source.quizMeta,
        );
      }),
    );
  }

  List<ChatMessage> _rebuildMessages(SessionDetail detail) {
    return List<ChatMessage>.unmodifiable(
      detail.messages
          .where((message) =>
              message.role == 'user' || message.role == 'assistant')
          .map((message) {
        final capability = message.capability == 'deep_question'
            ? ChatCapability.deepQuestion
            : ChatCapability.chat;
        final questions = message.role == 'assistant'
            ? extractQuizFromEvents(message.events)
            : const <QuizQuestion>[];
        final askUserState = message.role == 'assistant'
            ? _askUserFromStoredEvents(message.events)
            : null;
        return ChatMessage(
          id: message.id.isEmpty ? _nextMessageId(message.role) : message.id,
          role: message.role == 'user' ? ChatRole.user : ChatRole.assistant,
          textBuffer: message.content,
          capability: capability,
          quizQuestions: questions,
          quizMeta: _summaryFromEvents(message.events),
          askUser: askUserState?.$1,
          askUserToolCallId: askUserState?.$2,
          askUserResolved: askUserState?.$3 ?? false,
        );
      }),
    );
  }

  /// Recover (payload, tool_call_id, resolved) for the last ask_user card
  /// from a server-side event log, or null when the turn never asked.
  static (Map<String, dynamic>, String?, bool)? _askUserFromStoredEvents(
    List<Map<String, dynamic>> events,
  ) {
    Map<String, dynamic>? askUser;
    String? toolCallId;
    var resolved = false;
    for (final event in events) {
      final metadata = event['metadata'];
      if (metadata is! Map) continue;
      final typed = metadata.map((key, value) => MapEntry(key.toString(), value));
      if (event['type'] == 'tool_result' && typed['tool'] == 'ask_user') {
        final payload = _askUserFromToolMetadata(typed);
        if (payload != null) {
          askUser = payload;
          toolCallId = typed['tool_call_id']?.toString();
          resolved = false;
        }
      } else if (event['type'] == 'progress' &&
          typed['ask_user_resolved'] == true) {
        resolved = true;
      }
    }
    if (askUser == null) return null;
    return (askUser, toolCallId, resolved);
  }

  static Map<String, dynamic>? _summaryFromEvents(
    List<Map<String, dynamic>> events,
  ) {
    for (final event in events.reversed) {
      if (event['type'] != 'result') continue;
      final metadata = event['metadata'];
      if (metadata is! Map || metadata['summary'] is! Map) continue;
      return (metadata['summary'] as Map)
          .map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  static String? _eventValue(UnifiedEvent event, String key) {
    final direct = event.raw[key]?.toString().trim() ?? '';
    if (direct.isNotEmpty) return direct;
    final nested = event.metadata[key]?.toString().trim() ?? '';
    return nested.isEmpty ? null : nested;
  }

  String _nextMessageId(String prefix) {
    _messageSequence += 1;
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_messageSequence';
  }
}
