import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/attempt_api.dart';
import '../../api/judge_ws.dart';
import '../../api/voice_api.dart';
import '../../models/judge_result.dart';
import '../../models/quiz_attempt.dart';
import '../../models/quiz_question.dart';
import '../../services/attempt_history_store.dart';
import '../../services/audio_recorder.dart';
import '../../widgets/streaming_text.dart';
import '../../widgets/voice_recorder.dart';

class QuizAnswerPage extends StatefulWidget {
  const QuizAnswerPage({
    super.key,
    required this.question,
    required this.voiceApi,
    required this.judgeClient,
    required this.historyStore,
    this.attemptRepository,
    this.recorder,
    this.language = 'zh',
    this.onUnauthorized,
  });

  final QuizQuestion question;
  final VoiceApi voiceApi;
  final JudgeWsClient judgeClient;
  final AttemptHistoryStore historyStore;
  final AttemptRepository? attemptRepository;
  final AudioRecorderService? recorder;
  final String language;
  final VoidCallback? onUnauthorized;

  @override
  State<QuizAnswerPage> createState() => _QuizAnswerPageState();
}

class _QuizAnswerPageState extends State<QuizAnswerPage> {
  final TextEditingController _answerController = TextEditingController();
  late final AudioRecorderService _recorder =
      widget.recorder ?? AudioRecorderService();
  StreamSubscription<JudgeEvent>? _judgeSubscription;

  bool _transcribing = false;
  bool _judging = false;
  String _judgeText = '';
  String? _status;
  String? _error;
  JudgeResult? _result;

  Future<void> _transcribe(String path) async {
    if (_transcribing) return;
    setState(() {
      _transcribing = true;
      _error = null;
      _status = '正在上传并转写录音…';
    });
    try {
      final text = await widget.voiceApi.transcribe(
        filePath: path,
        language: widget.language,
      );
      if (!mounted) return;
      _answerController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      setState(() => _status = '转写完成，可继续编辑答案。');
    } on VoiceApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
      if (error.failure == VoiceApiFailure.unauthorized) {
        widget.onUnauthorized?.call();
      }
    } catch (_) {
      if (mounted) setState(() => _error = '语音转写失败，请检查网络后重试。');
    } finally {
      await _recorder.removeTemporaryRecording(path);
      if (mounted) setState(() => _transcribing = false);
    }
  }

  Future<void> _judge() async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty) {
      setState(() => _error = '请先填写或录入答案。');
      return;
    }
    await _judgeSubscription?.cancel();
    setState(() {
      _judging = true;
      _judgeText = '';
      _result = null;
      _error = null;
      _status = '正在连接评判服务…';
    });
    _judgeSubscription = widget.judgeClient
        .judge(
      question: widget.question,
      userAnswer: answer,
      language: widget.language,
    )
        .listen(
      (event) async {
        if (!mounted) return;
        switch (event.type) {
          case JudgeEventType.connecting:
            setState(() => _status = '正在连接评判服务…');
            break;
          case JudgeEventType.reconnecting:
            setState(
              () => _status = '连接失败，正在进行第 ${event.retryAttempt} 次重连…',
            );
            break;
          case JudgeEventType.started:
            setState(() => _status = 'AI 正在评判…');
            break;
          case JudgeEventType.text:
            setState(() => _judgeText = event.accumulatedText);
            break;
          case JudgeEventType.done:
            final result =
                event.result ?? JudgeResult.fromText(event.accumulatedText);
            final attempt = QuizAttempt.create(
              question: widget.question,
              userAnswer: answer,
              result: result,
            );
            setState(() {
              _judgeText = result.text;
              _result = result;
              _judging = false;
              _status = '评判完成，正在保存本机历史记录…';
            });
            try {
              await widget.historyStore.save(attempt);
              final attemptRepository = widget.attemptRepository;
              if (attemptRepository == null) {
                if (mounted) {
                  setState(() => _status = '评判完成，已保存到本机历史记录。');
                }
                break;
              }
              if (mounted) {
                setState(() => _status = '评判完成，正在同步服务端历史记录…');
              }
              try {
                await attemptRepository.saveAttempt(attempt);
                if (mounted) {
                  setState(() => _status = '评判完成，已同步到服务端历史记录。');
                }
              } catch (_) {
                if (mounted) {
                  setState(
                    () => _status = '评判完成，本机已保存；服务端同步失败，稍后可重试。',
                  );
                }
              }
            } catch (_) {
              if (mounted) {
                setState(() => _error = '评判已完成，但本机历史记录保存失败。');
              }
            }
            break;
          case JudgeEventType.error:
            setState(() {
              _judgeText = event.accumulatedText;
              _judging = false;
              _error = event.content;
              _status = null;
            });
            if (event.unauthorized) widget.onUnauthorized?.call();
            break;
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _judging = false;
          _error = '评判连接发生异常，请检查网络后重试。';
        });
      },
      onDone: () {
        if (mounted && _judging) setState(() => _judging = false);
      },
    );
  }

  @override
  void dispose() {
    _answerController.dispose();
    unawaited(_judgeSubscription?.cancel());
    unawaited(widget.judgeClient.cancel());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('作答与评判')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text('题目', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(widget.question.question),
            if (widget.question.options.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              ...widget.question.options.entries.map(
                (option) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('${option.key}. ${option.value}'),
                ),
              ),
            ],
            const SizedBox(height: 24),
            VoiceRecorder(
              recorder: _recorder,
              onRecordingComplete: _transcribe,
              enabled: !_judging && !_transcribing,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _answerController,
              enabled: !_judging,
              minLines: 4,
              maxLines: 8,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                labelText: '你的答案',
                hintText: '可手动输入，也可录音转写后继续编辑',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _judging || _transcribing ? null : _judge,
              icon: _judging
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: Text(_judging ? '评判中…' : '提交 AI 评判'),
            ),
            if (_status != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(_status!, semanticsLabel: _status),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_judgeText.isNotEmpty || _judging) ...<Widget>[
              const SizedBox(height: 24),
              Text('AI 评判', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              StreamingText(
                text: _judgeText,
                isStreaming: _judging,
                result: _result,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
