import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

import '../models/quiz_question.dart';

typedef AccessTokenLoader = Future<String?> Function();
typedef WebSocketConnector = WebSocketChannel Function(Uri uri);

class QuizGenerationRequest {
  const QuizGenerationRequest({
    required this.knowledgeBaseName,
    required this.knowledgePoint,
    required this.preference,
    required this.difficulty,
    required this.questionType,
    required this.count,
  });

  final String knowledgeBaseName;
  final String knowledgePoint;
  final String preference;
  final String difficulty;
  final String questionType;
  final int count;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'requirement': <String, dynamic>{
          'knowledge_point': knowledgePoint,
          'preference': preference,
          'difficulty': difficulty,
          'question_type': questionType,
        },
        'kb_name': knowledgeBaseName,
        'count': count,
      };

  @override
  bool operator ==(Object other) {
    return other is QuizGenerationRequest &&
        other.knowledgeBaseName == knowledgeBaseName &&
        other.knowledgePoint == knowledgePoint &&
        other.preference == preference &&
        other.difficulty == difficulty &&
        other.questionType == questionType &&
        other.count == count;
  }

  @override
  int get hashCode => Object.hash(
        knowledgeBaseName,
        knowledgePoint,
        preference,
        difficulty,
        questionType,
        count,
      );
}

enum QuestionStreamEventType {
  connected,
  taskId,
  status,
  progress,
  question,
  batchSummary,
  result,
  complete,
  error,
}

class QuestionStreamEvent {
  const QuestionStreamEvent({
    required this.type,
    this.message = '',
    this.taskId,
    this.question,
    this.requested,
    this.completed,
    this.failed,
    this.payload = const <String, dynamic>{},
  });

  final QuestionStreamEventType type;
  final String message;
  final String? taskId;
  final QuizQuestion? question;
  final int? requested;
  final int? completed;
  final int? failed;
  final Map<String, dynamic> payload;
}

abstract interface class QuestionGenerationGateway {
  Stream<QuestionStreamEvent> generate(QuizGenerationRequest request);
}

class QuestionWsClient implements QuestionGenerationGateway {
  QuestionWsClient({
    required this.baseUrl,
    required AccessTokenLoader tokenLoader,
    WebSocketConnector? connector,
    this.maxReconnectAttempts = 2,
    this.connectTimeout = const Duration(seconds: 10),
    this.closeTimeout = const Duration(seconds: 1),
    this.retryDelay = const Duration(milliseconds: 400),
  })  : _tokenLoader = tokenLoader,
        _connector = connector ??
            ((uri) => IOWebSocketChannel.connect(
                  uri,
                  connectTimeout: connectTimeout,
                ));

  static const generationPath = '/api/v1/question/generate';

  final String baseUrl;
  final AccessTokenLoader _tokenLoader;
  final WebSocketConnector _connector;
  final int maxReconnectAttempts;
  final Duration connectTimeout;
  final Duration closeTimeout;
  final Duration retryDelay;

  @override
  Stream<QuestionStreamEvent> generate(QuizGenerationRequest request) async* {
    final token = (await _tokenLoader())?.trim();
    final uri = _generationUri(token);
    for (var attempt = 0; attempt <= maxReconnectAttempts; attempt++) {
      WebSocketChannel? channel;
      var receivedServerEvent = false;
      try {
        channel = _connector(uri);
        await channel.ready.timeout(connectTimeout);
        yield QuestionStreamEvent(
          type: QuestionStreamEventType.connected,
          message: attempt == 0 ? '已连接，正在提交出题要求…' : '网络已恢复，正在重新生成题目…',
        );
        channel.sink.add(jsonEncode(request.toJson()));

        await for (final raw in channel.stream) {
          receivedServerEvent = true;
          final events = _parseMessage(raw);
          for (final event in events) {
            yield event;
            if (event.type == QuestionStreamEventType.error ||
                event.type == QuestionStreamEventType.complete) {
              return;
            }
          }
        }

        if (channel.closeCode == 4001) {
          throw const QuestionUnauthorizedException();
        }
        if (receivedServerEvent || attempt == maxReconnectAttempts) {
          throw const QuestionConnectionException('出题连接已断开，请重新生成。');
        }
      } on QuestionConnectionException {
        rethrow;
      } on FormatException catch (error) {
        throw QuestionConnectionException('出题服务返回了无效数据：${error.message}');
      } on TimeoutException {
        if (attempt == maxReconnectAttempts) {
          throw const QuestionConnectionException('连接出题服务超时，请检查网络后重试。');
        }
      } on WebSocketChannelException catch (error) {
        if (_isUnauthorizedFailure(error, channel?.closeCode, token)) {
          throw const QuestionUnauthorizedException();
        }
        if (receivedServerEvent || attempt == maxReconnectAttempts) {
          throw const QuestionConnectionException(
            '无法连接出题服务，请检查网络和服务器地址后重试。',
          );
        }
      } catch (error) {
        if (_isUnauthorizedFailure(error, channel?.closeCode, token)) {
          throw const QuestionUnauthorizedException();
        }
        if (receivedServerEvent || attempt == maxReconnectAttempts) {
          throw QuestionConnectionException('无法连接出题服务：$error');
        }
      } finally {
        await _closeChannel(channel);
      }

      if (retryDelay > Duration.zero) {
        await Future<void>.delayed(retryDelay * (attempt + 1));
      }
    }
  }

  Future<void> _closeChannel(WebSocketChannel? channel) async {
    if (channel == null) return;
    try {
      await channel.sink.close().timeout(closeTimeout);
    } on Object {
      // A socket that never completed its handshake can also leave close()
      // pending forever. The connection itself has a deadline, so cleanup
      // must be bounded as well to guarantee a terminal UI state offline.
    }
  }

  Uri _generationUri(String? token) {
    final rawBase = baseUrl.trim();
    if (rawBase.isEmpty) {
      throw const QuestionConnectionException('服务器地址为空。');
    }
    final base = Uri.parse(rawBase);
    if (!base.hasAuthority || base.host.isEmpty) {
      throw const QuestionConnectionException('服务器地址格式无效。');
    }
    final scheme = switch (base.scheme.toLowerCase()) {
      'https' => 'wss',
      'http' => 'ws',
      'wss' => 'wss',
      'ws' => 'ws',
      _ => throw const QuestionConnectionException('服务器地址格式无效。'),
    };
    final basePath = base.path.replaceFirst(RegExp(r'/+$'), '');
    final apiPath =
        basePath.endsWith('/api/v1') ? basePath : '$basePath/api/v1';
    return base.replace(
      scheme: scheme,
      path: '$apiPath/question/generate',
      queryParameters: <String, String>{
        ...base.queryParameters,
        if (token != null && token.isNotEmpty) 'token': token,
      },
      fragment: null,
    );
  }

  static List<QuestionStreamEvent> _parseMessage(Object? raw) {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is! Map) {
      throw const FormatException('WebSocket event must be a JSON object.');
    }
    final payload = decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final type = payload['type']?.toString() ?? '';
    switch (type) {
      case 'task_id':
        return <QuestionStreamEvent>[
          QuestionStreamEvent(
            type: QuestionStreamEventType.taskId,
            taskId: payload['task_id']?.toString(),
            payload: payload,
          ),
        ];
      case 'status':
        return <QuestionStreamEvent>[
          QuestionStreamEvent(
            type: QuestionStreamEventType.status,
            message: _message(payload, fallback: '正在生成题目…'),
            payload: payload,
          ),
        ];
      case 'progress':
      case 'process_log':
      case 'stage_start':
      case 'stage_end':
      case 'thinking':
      case 'observation':
        return <QuestionStreamEvent>[
          QuestionStreamEvent(
            type: QuestionStreamEventType.progress,
            message: _message(payload, fallback: '正在生成题目…'),
            payload: payload,
          ),
        ];
      case 'content':
        final question = _questionFromContent(payload);
        if (question == null) {
          return <QuestionStreamEvent>[
            QuestionStreamEvent(
              type: QuestionStreamEventType.progress,
              message: _message(payload, fallback: '正在组织题目…'),
              payload: payload,
            ),
          ];
        }
        return <QuestionStreamEvent>[
          QuestionStreamEvent(
            type: QuestionStreamEventType.question,
            question: question,
            payload: payload,
          ),
        ];
      case 'question':
        if (payload['success'] == false) {
          return <QuestionStreamEvent>[
            QuestionStreamEvent(
              type: QuestionStreamEventType.progress,
              message: _message(payload, fallback: '一道题生成失败，正在继续生成其余题目…'),
              payload: payload,
            ),
          ];
        }
        final value = payload['question'];
        final questionJson = value is Map
            ? value.map((key, item) => MapEntry(key.toString(), item))
            : payload;
        return <QuestionStreamEvent>[
          QuestionStreamEvent(
            type: QuestionStreamEventType.question,
            question: QuizQuestion.fromJson(questionJson),
            payload: payload,
          ),
        ];
      case 'result':
        return <QuestionStreamEvent>[
          ..._questionsFromResult(payload).map(
            (question) => QuestionStreamEvent(
              type: QuestionStreamEventType.question,
              question: question,
              payload: payload,
            ),
          ),
          QuestionStreamEvent(
            type: QuestionStreamEventType.result,
            payload: payload,
          ),
        ];
      case 'batch_summary':
        return <QuestionStreamEvent>[
          QuestionStreamEvent(
            type: QuestionStreamEventType.batchSummary,
            requested: _int(payload['requested']),
            completed: _int(payload['completed']),
            failed: _int(payload['failed']),
            payload: payload,
          ),
        ];
      case 'complete':
      case 'done':
        return <QuestionStreamEvent>[
          QuestionStreamEvent(
            type: QuestionStreamEventType.complete,
            payload: payload,
          ),
        ];
      case 'error':
        return <QuestionStreamEvent>[
          QuestionStreamEvent(
            type: QuestionStreamEventType.error,
            message: _message(payload, fallback: '题目生成失败，请重试。'),
            payload: payload,
          ),
        ];
      default:
        return <QuestionStreamEvent>[
          QuestionStreamEvent(
            type: QuestionStreamEventType.progress,
            message: _message(payload, fallback: '正在生成题目…'),
            payload: payload,
          ),
        ];
    }
  }

  static QuizQuestion? _questionFromContent(Map<String, dynamic> payload) {
    final metadata = _map(payload['metadata']);
    if (metadata?['call_kind'] != 'quiz_question_emitted') return null;
    final qaPair = _map(metadata?['qa_pair']);
    return qaPair == null ? null : QuizQuestion.fromJson(qaPair);
  }

  static Iterable<QuizQuestion> _questionsFromResult(
    Map<String, dynamic> payload,
  ) sync* {
    final metadata = _map(payload['metadata']);
    final summary = _map(metadata?['summary']) ?? _map(payload['summary']);
    final results = summary?['results'];
    if (results is! Iterable) return;
    for (final result in results) {
      final item = _map(result);
      final qaPair = _map(item?['qa_pair']);
      if (qaPair == null) continue;
      yield QuizQuestion.fromJson(qaPair);
    }
  }

  static Map<String, dynamic>? _map(Object? value) {
    if (value is! Map) return null;
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String _message(
    Map<String, dynamic> payload, {
    required String fallback,
  }) {
    for (final key in const <String>['content', 'message', 'detail']) {
      final value = payload[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return fallback;
  }

  static bool _isUnauthorizedFailure(
    Object error,
    int? closeCode,
    String? token,
  ) {
    if (closeCode == 4001) return true;
    if (token == null || token.isEmpty) return false;
    final message = error.toString().toLowerCase();
    return message.contains('4001') ||
        message.contains('unauthorized') ||
        message.contains('forbidden') ||
        RegExp(r'\b(?:401|403)\b').hasMatch(message);
  }
}

class QuestionConnectionException implements Exception {
  const QuestionConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class QuestionUnauthorizedException extends QuestionConnectionException {
  const QuestionUnauthorizedException() : super('登录已失效，请重新登录。');
}
