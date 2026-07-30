import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

import '../models/judge_result.dart';
import '../models/quiz_question.dart';

typedef JudgeChannelFactory = WebSocketChannel Function(Uri uri);

enum JudgeEventType { connecting, reconnecting, started, text, done, error }

class JudgeEvent {
  const JudgeEvent(
    this.type, {
    this.content = '',
    this.accumulatedText = '',
    this.result,
    this.unauthorized = false,
    this.retryAttempt = 0,
  });

  final JudgeEventType type;
  final String content;
  final String accumulatedText;
  final JudgeResult? result;
  final bool unauthorized;
  final int retryAttempt;
}

class JudgeWsClient {
  JudgeWsClient({
    required Uri endpoint,
    required String token,
    JudgeChannelFactory? channelFactory,
    this.maxReconnectAttempts = 2,
    this.connectTimeout = const Duration(seconds: 10),
    this.closeTimeout = const Duration(seconds: 1),
  })  : _endpoint = endpoint,
        _token = token,
        _channelFactory = channelFactory ??
            ((uri) => IOWebSocketChannel.connect(
                  uri,
                  connectTimeout: connectTimeout,
                ));

  factory JudgeWsClient.fromBaseUri({
    required Uri baseUri,
    required String token,
    JudgeChannelFactory? channelFactory,
    int maxReconnectAttempts = 2,
  }) {
    final scheme = switch (baseUri.scheme.toLowerCase()) {
      'https' || 'wss' => 'wss',
      _ => 'ws',
    };
    final basePath = baseUri.path.replaceFirst(RegExp(r'/+$'), '');
    final apiPath =
        basePath.endsWith('/api/v1') ? basePath : '$basePath/api/v1';
    return JudgeWsClient(
      endpoint: baseUri.replace(
        scheme: scheme,
        path: '$apiPath/question/judge',
        query: null,
        fragment: null,
      ),
      token: token,
      channelFactory: channelFactory,
      maxReconnectAttempts: maxReconnectAttempts,
    );
  }

  final Uri _endpoint;
  final String _token;
  final JudgeChannelFactory _channelFactory;
  final int maxReconnectAttempts;
  final Duration connectTimeout;
  final Duration closeTimeout;

  WebSocketChannel? _activeChannel;
  bool _cancelled = false;

  Stream<JudgeEvent> judge({
    required QuizQuestion question,
    required String userAnswer,
    String language = 'zh',
  }) async* {
    _cancelled = false;
    final trimmedAnswer = userAnswer.trim();
    if (trimmedAnswer.isEmpty) {
      yield const JudgeEvent(JudgeEventType.error, content: '请先填写或录入答案。');
      return;
    }

    final request = <String, dynamic>{
      'question': question.question,
      'question_type': question.questionType,
      'options': question.options.isEmpty ? null : question.options,
      'correct_answer': question.correctAnswer,
      'explanation': question.explanation,
      'user_answer': trimmedAnswer,
      'language': language,
    };

    for (var attempt = 0; attempt <= maxReconnectAttempts; attempt++) {
      if (_cancelled) return;
      yield JudgeEvent(
        attempt == 0 ? JudgeEventType.connecting : JudgeEventType.reconnecting,
        retryAttempt: attempt,
      );

      var receivedServerEvent = false;
      var aggregate = '';
      try {
        final uri = _endpoint.replace(
          queryParameters: <String, String>{
            ..._endpoint.queryParameters,
            if (_token.isNotEmpty) 'token': _token,
          },
        );
        final channel = _channelFactory(uri);
        _activeChannel = channel;
        await channel.ready.timeout(connectTimeout);
        if (_cancelled) {
          await _closeChannel(channel);
          return;
        }
        channel.sink.add(jsonEncode(request));

        await for (final raw in channel.stream) {
          if (_cancelled) return;
          final event = _decodeEvent(raw);
          if (event == null) continue;
          receivedServerEvent = true;

          switch (event.type) {
            case JudgeEventType.started:
              yield const JudgeEvent(JudgeEventType.started);
              break;
            case JudgeEventType.text:
              aggregate += event.content;
              yield JudgeEvent(
                JudgeEventType.text,
                content: event.content,
                accumulatedText: aggregate,
              );
              break;
            case JudgeEventType.done:
              if (aggregate.trim().isEmpty) {
                yield const JudgeEvent(
                  JudgeEventType.error,
                  content: '评判服务已结束，但没有返回评判文字，请重试。',
                );
                return;
              }
              final result = JudgeResult.fromText(aggregate);
              yield JudgeEvent(
                JudgeEventType.done,
                accumulatedText: aggregate,
                result: result,
              );
              return;
            case JudgeEventType.error:
              yield JudgeEvent(
                JudgeEventType.error,
                content: event.content.isEmpty ? 'AI 评判失败，请重试。' : event.content,
                accumulatedText: aggregate,
              );
              return;
            case JudgeEventType.connecting:
            case JudgeEventType.reconnecting:
              break;
          }
        }

        final closeCode = channel.closeCode;
        if (closeCode == 4001) {
          yield const JudgeEvent(
            JudgeEventType.error,
            content: '登录已失效，请重新登录。',
            unauthorized: true,
          );
          return;
        }
        if (receivedServerEvent || attempt == maxReconnectAttempts) {
          yield JudgeEvent(
            JudgeEventType.error,
            content: aggregate.isEmpty
                ? '评判连接已断开，请检查网络后重试。'
                : '评判连接中断，已保留当前返回内容，请手动重试。',
            accumulatedText: aggregate,
          );
          return;
        }
      } on TimeoutException {
        if (attempt == maxReconnectAttempts) {
          yield const JudgeEvent(
            JudgeEventType.error,
            content: '连接评判服务超时，请检查网络后重试。',
          );
          return;
        }
      } catch (error) {
        if (_isUnauthorizedFailure(error, _activeChannel?.closeCode)) {
          yield const JudgeEvent(
            JudgeEventType.error,
            content: '登录已失效，请重新登录。',
            unauthorized: true,
          );
          return;
        }
        if (receivedServerEvent || attempt == maxReconnectAttempts) {
          yield JudgeEvent(
            JudgeEventType.error,
            content: receivedServerEvent
                ? '评判连接中断，已保留当前返回内容，请手动重试。'
                : '无法连接评判服务，请检查网络后重试。',
            accumulatedText: aggregate,
          );
          return;
        }
      } finally {
        final channel = _activeChannel;
        _activeChannel = null;
        if (channel != null) {
          await _closeChannel(channel);
        }
      }

      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    final channel = _activeChannel;
    _activeChannel = null;
    await _closeChannel(channel);
  }

  Future<void> _closeChannel(WebSocketChannel? channel) async {
    if (channel == null) return;
    try {
      await channel.sink.close().timeout(closeTimeout);
    } on Object {
      // Keep cancellation and offline failure bounded even if the transport
      // never completed its opening handshake.
    }
  }

  static JudgeEvent? _decodeEvent(Object? raw) {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map) return null;
      final type = decoded['type']?.toString();
      final content = decoded['content']?.toString() ?? '';
      return switch (type) {
        'started' => const JudgeEvent(JudgeEventType.started),
        'text' => JudgeEvent(JudgeEventType.text, content: content),
        'done' => const JudgeEvent(JudgeEventType.done),
        'error' => JudgeEvent(JudgeEventType.error, content: content),
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  bool _isUnauthorizedFailure(Object error, int? closeCode) {
    if (closeCode == 4001) return true;
    if (_token.isEmpty) return false;
    final message = error.toString().toLowerCase();
    return message.contains('4001') ||
        message.contains('unauthorized') ||
        message.contains('forbidden') ||
        RegExp(r'\b(?:401|403)\b').hasMatch(message);
  }
}
