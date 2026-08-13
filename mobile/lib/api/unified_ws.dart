import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef AccessTokenLoader = Future<String?> Function();
typedef UnifiedWebSocketConnector = WebSocketChannel Function(Uri uri);

enum UnifiedEventType {
  stageStart,
  stageEnd,
  thinking,
  observation,
  content,
  toolCall,
  toolResult,
  progress,
  sources,
  result,
  error,
  session,
  sessionMeta,
  done,
  waitForInput,
  activeTurnInfo,
  pong,
  unknown,
}

class UnifiedEvent {
  const UnifiedEvent({
    required this.type,
    required this.content,
    required this.metadata,
    required this.sessionId,
    required this.turnId,
    required this.seq,
    required this.raw,
  });

  final UnifiedEventType type;
  final String content;
  final Map<String, dynamic> metadata;
  final String? sessionId;
  final String? turnId;
  final int seq;
  final Map<String, dynamic> raw;

  factory UnifiedEvent.parse(Object? raw) {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is! Map) {
      throw const FormatException('Unified WebSocket event must be an object.');
    }
    final envelope = decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final rawMetadata = envelope['metadata'];
    final metadata = rawMetadata is Map
        ? rawMetadata.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    final rawSeq = envelope['seq'];
    final seq = switch (rawSeq) {
      int number => number,
      num number => number.toInt(),
      _ => int.tryParse('$rawSeq') ?? 0,
    };
    return UnifiedEvent(
      type: _eventType(envelope['type']?.toString()),
      content: envelope['content']?.toString() ?? '',
      metadata: Map<String, dynamic>.unmodifiable(metadata),
      sessionId: _optionalString(envelope['session_id']),
      turnId: _optionalString(envelope['turn_id']),
      seq: seq,
      raw: Map<String, dynamic>.unmodifiable(envelope),
    );
  }

  static UnifiedEventType _eventType(String? type) => switch (type) {
        'stage_start' => UnifiedEventType.stageStart,
        'stage_end' => UnifiedEventType.stageEnd,
        'thinking' => UnifiedEventType.thinking,
        'observation' => UnifiedEventType.observation,
        'content' => UnifiedEventType.content,
        'tool_call' => UnifiedEventType.toolCall,
        'tool_result' => UnifiedEventType.toolResult,
        'progress' => UnifiedEventType.progress,
        'sources' => UnifiedEventType.sources,
        'result' => UnifiedEventType.result,
        'error' => UnifiedEventType.error,
        'session' => UnifiedEventType.session,
        'session_meta' => UnifiedEventType.sessionMeta,
        'done' => UnifiedEventType.done,
        'wait_for_input' => UnifiedEventType.waitForInput,
        'active_turn_info' => UnifiedEventType.activeTurnInfo,
        'pong' => UnifiedEventType.pong,
        _ => UnifiedEventType.unknown,
      };

  static String? _optionalString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

class UnifiedChatClient {
  UnifiedChatClient({
    required this.baseUrl,
    required AccessTokenLoader tokenLoader,
    UnifiedWebSocketConnector? connector,
    this.connectTimeout = const Duration(seconds: 10),
    this.pingInterval = const Duration(seconds: 25),
    this.maxReconnectAttempts = 5,
  })  : _tokenLoader = tokenLoader,
        _connector = connector ??
            ((uri) => IOWebSocketChannel.connect(
                  uri,
                  connectTimeout: connectTimeout,
                ));

  final String baseUrl;
  final AccessTokenLoader _tokenLoader;
  final UnifiedWebSocketConnector _connector;
  final Duration connectTimeout;
  final Duration pingInterval;
  final int maxReconnectAttempts;

  final StreamController<UnifiedEvent> _events =
      StreamController<UnifiedEvent>.broadcast(sync: true);
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _socketSubscription;
  Timer? _heartbeat;
  Timer? _reconnectTimer;
  Future<void>? _connecting;
  DateTime? _lastReceivedAt;
  String? _lastTurnId;
  int _lastSeq = 0;
  final Set<String> _cancelledTurnIds = <String>{};
  int _reconnectAttempts = 0;
  bool _disposed = false;
  bool _intentionalClose = false;

  Stream<UnifiedEvent> get events => _events.stream;
  bool get isConnected => _channel != null;

  Future<void> connect() {
    if (_disposed) {
      return Future<void>.error(
        const UnifiedConnectionException('聊天连接已经关闭。'),
      );
    }
    if (isConnected) return Future<void>.value();
    return _connecting ??= _open().whenComplete(() => _connecting = null);
  }

  Future<void> reconnect() async {
    if (_disposed) {
      throw const UnifiedConnectionException('聊天连接已经关闭。');
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    await _closeSocket(clearIntentional: false);
    await connect();
  }

  Future<void> _open() async {
    final token = (await _tokenLoader())?.trim();
    final uri = _endpoint(token);
    WebSocketChannel? channel;
    try {
      channel = _connector(uri);
      await channel.ready.timeout(connectTimeout);
      if (_disposed) {
        await channel.sink.close();
        return;
      }
      _intentionalClose = false;
      _channel = channel;
      _lastReceivedAt = DateTime.now();
      _socketSubscription = channel.stream.listen(
        _handleRawEvent,
        onError: _handleSocketError,
        onDone: _handleSocketDone,
        cancelOnError: false,
      );
      _startHeartbeat();
      final turnId = _lastTurnId;
      if (turnId != null) {
        _sendNow(<String, dynamic>{
          'type': 'resume_from',
          'turn_id': turnId,
          'seq': _lastSeq,
        });
      }
    } on TimeoutException {
      await channel?.sink.close();
      throw const UnifiedConnectionException('连接聊天服务超时，请检查网络后重试。');
    } catch (error) {
      await channel?.sink.close();
      if (_isUnauthorizedFailure(error, channel?.closeCode, token)) {
        throw const UnifiedUnauthorized();
      }
      if (error is UnifiedConnectionException) rethrow;
      throw UnifiedConnectionException('无法连接聊天服务：$error');
    }
  }

  Future<void> startTurn({
    required String content,
    String capability = 'chat',
    List<String> knowledgeBases = const <String>[],
    String? sessionId,
    Map<String, dynamic>? config,
    String language = 'zh',
  }) async {
    await _send(<String, dynamic>{
      'type': 'start_turn',
      'content': content,
      'capability': capability,
      'knowledge_bases': knowledgeBases,
      'session_id': sessionId ?? '',
      'language': language,
      if (config != null) 'config': config,
    });
  }

  Future<void> resumeFrom({required String turnId, required int seq}) async {
    await _send(<String, dynamic>{
      'type': 'resume_from',
      'turn_id': turnId,
      'seq': seq,
    });
    _lastTurnId = turnId;
    _lastSeq = max(0, seq);
  }

  Future<void> checkActiveTurn(String sessionId) {
    return _send(<String, dynamic>{
      'type': 'check_active_turn',
      'session_id': sessionId,
    });
  }

  Future<void> submitUserReply({
    required String turnId,
    required String text,
    List<Map<String, String>>? answers,
  }) {
    return _send(<String, dynamic>{
      'type': 'submit_user_reply',
      'turn_id': turnId,
      'text': text,
      if (answers != null && answers.isNotEmpty) 'answers': answers,
    });
  }

  Future<void> cancelTurn(String turnId) async {
    final wasLastTurn = _lastTurnId == turnId;
    final previousSeq = _lastSeq;
    _cancelledTurnIds.add(turnId);
    if (wasLastTurn) {
      _lastTurnId = null;
      _lastSeq = 0;
    }
    try {
      await _send(<String, dynamic>{
        'type': 'cancel_turn',
        'turn_id': turnId,
      });
    } on Object {
      _cancelledTurnIds.remove(turnId);
      if (wasLastTurn) {
        _lastTurnId = turnId;
        _lastSeq = previousSeq;
      }
      rethrow;
    }
  }

  Future<void> _send(Map<String, dynamic> payload) async {
    await connect();
    _sendNow(payload);
  }

  void _sendNow(Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null || _disposed) {
      throw const UnifiedConnectionException('聊天连接尚未建立。');
    }
    channel.sink.add(jsonEncode(payload));
  }

  void _handleRawEvent(Object? raw) {
    _lastReceivedAt = DateTime.now();
    try {
      final event = UnifiedEvent.parse(raw);
      _reconnectAttempts = 0;
      final turnId = event.turnId ?? event.metadata['turn_id']?.toString();
      final cancelled = turnId != null && _cancelledTurnIds.contains(turnId);
      if (!cancelled && turnId != null && turnId.trim().isNotEmpty) {
        _lastTurnId = turnId;
      }
      if (!cancelled && event.seq > _lastSeq) _lastSeq = event.seq;
      if (!cancelled && !_events.isClosed) _events.add(event);
      final terminal = event.type == UnifiedEventType.done ||
          (event.type == UnifiedEventType.error &&
              event.metadata['turn_terminal'] == true);
      if (event.type == UnifiedEventType.done && cancelled) {
        _cancelledTurnIds.remove(turnId);
      }
      if (terminal && !cancelled && (turnId == null || turnId == _lastTurnId)) {
        _lastTurnId = null;
        _lastSeq = 0;
      }
    } on FormatException catch (error, stackTrace) {
      if (!_events.isClosed) _events.addError(error, stackTrace);
    }
  }

  void _handleSocketError(Object error, StackTrace stackTrace) {
    final channel = _channel;
    if (_isUnauthorizedFailure(error, channel?.closeCode, null)) {
      if (!_events.isClosed) _events.addError(const UnifiedUnauthorized());
      _intentionalClose = true;
      unawaited(_closeSocket(clearIntentional: false));
      return;
    }
    if (!_events.isClosed) {
      _events.addError(
        const UnifiedConnectionException('聊天连接中断，正在尝试恢复。'),
        stackTrace,
      );
    }
    unawaited(_restartConnection());
  }

  void _handleSocketDone() {
    final closeCode = _channel?.closeCode;
    final unauthorized = closeCode == 4001;
    unawaited(_closeSocket(clearIntentional: false).whenComplete(() {
      if (unauthorized) {
        if (!_events.isClosed) _events.addError(const UnifiedUnauthorized());
      } else if (!_disposed && !_intentionalClose) {
        _scheduleReconnect();
      }
    }));
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    if (pingInterval <= Duration.zero) return;
    _heartbeat = Timer.periodic(pingInterval, (_) {
      if (_disposed || _channel == null) return;
      final lastReceivedAt = _lastReceivedAt;
      if (lastReceivedAt != null &&
          DateTime.now().difference(lastReceivedAt) > pingInterval * 2) {
        unawaited(_restartConnection());
        return;
      }
      _sendNow(const <String, dynamic>{'type': 'ping'});
    });
  }

  Future<void> _restartConnection() async {
    await _closeSocket(clearIntentional: false);
    if (!_disposed) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _reconnectTimer?.isActive == true) return;
    if (_reconnectAttempts >= maxReconnectAttempts) {
      if (!_events.isClosed) {
        _events.addError(
          const UnifiedConnectionException('聊天连接恢复失败，请检查网络后重试。'),
        );
      }
      return;
    }
    final attempt = ++_reconnectAttempts;
    final seconds = min(1 << (attempt - 1), 16);
    _reconnectTimer = Timer(Duration(seconds: seconds), () async {
      try {
        await connect();
      } on UnifiedUnauthorized {
        if (!_events.isClosed) _events.addError(const UnifiedUnauthorized());
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  Uri _endpoint(String? token) {
    final rawBase = baseUrl.trim();
    if (rawBase.isEmpty) {
      throw const UnifiedConnectionException('服务器地址为空。');
    }
    final base = Uri.parse(rawBase);
    if (!base.hasAuthority || base.host.isEmpty) {
      throw const UnifiedConnectionException('服务器地址格式无效。');
    }
    final scheme = switch (base.scheme.toLowerCase()) {
      'https' || 'wss' => 'wss',
      'http' || 'ws' => 'ws',
      _ => throw const UnifiedConnectionException('服务器地址格式无效。'),
    };
    final basePath = base.path.replaceFirst(RegExp(r'/+$'), '');
    final apiPath =
        basePath.endsWith('/api/v1') ? basePath : '$basePath/api/v1';
    return base.replace(
      scheme: scheme,
      path: '$apiPath/ws',
      queryParameters: <String, String>{
        ...base.queryParameters,
        if (token != null && token.isNotEmpty) 'token': token,
      },
      fragment: null,
    );
  }

  Future<void> _closeSocket({bool clearIntentional = true}) async {
    _heartbeat?.cancel();
    _heartbeat = null;
    final subscription = _socketSubscription;
    _socketSubscription = null;
    await subscription?.cancel();
    final channel = _channel;
    _channel = null;
    try {
      await channel?.sink.close().timeout(const Duration(seconds: 1));
    } on Object {
      // Closing a half-open connection is best effort.
    }
    if (clearIntentional) _intentionalClose = false;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _intentionalClose = true;
    _reconnectTimer?.cancel();
    await _closeSocket(clearIntentional: false);
    await _events.close();
  }

  static bool _isUnauthorizedFailure(
    Object error,
    int? closeCode,
    String? token,
  ) {
    if (closeCode == 4001) return true;
    if (token != null && token.isEmpty) return false;
    final message = error.toString().toLowerCase();
    return message.contains('4001') ||
        message.contains('unauthorized') ||
        message.contains('forbidden') ||
        RegExp(r'\b(?:401|403)\b').hasMatch(message);
  }
}

class UnifiedUnauthorized implements Exception {
  const UnifiedUnauthorized();

  @override
  String toString() => '登录已失效，请重新登录。';
}

class UnifiedConnectionException implements Exception {
  const UnifiedConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}
