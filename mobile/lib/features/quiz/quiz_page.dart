import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../api/question_ws.dart';
import '../../models/quiz_question.dart';
import 'quiz_generation_controller.dart';

class QuizPage extends ConsumerStatefulWidget {
  const QuizPage({
    super.key,
    required this.request,
    this.onAnswerQuestion,
    this.onUnauthorized,
  });

  final QuizGenerationRequest request;
  final ValueChanged<QuizQuestion>? onAnswerQuestion;
  final VoidCallback? onUnauthorized;

  @override
  ConsumerState<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends ConsumerState<QuizPage>
    with WidgetsBindingObserver {
  late final QuizGenerationController _generationController;

  @override
  void initState() {
    super.initState();
    _generationController = ref.read(quizGenerationControllerProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_setWakelock(enabled: true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        _generationController.start(widget.request),
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_setWakelock(enabled: true));
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      // Mobile OSes can suspend a socket without a clean close. Cancel the
      // foreground-only generation so the existing retry action can start a
      // fresh, deterministic request when the learner returns.
      unawaited(_generationController.cancel());
      unawaited(_setWakelock(enabled: false));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_generationController.cancel());
    unawaited(_setWakelock(enabled: false));
    super.dispose();
  }

  Future<void> _setWakelock({required bool enabled}) async {
    try {
      if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } on Object {
      // Wakelock improves long generations but must never block the quiz flow
      // if a platform implementation is unavailable.
    }
  }

  @override
  void didUpdateWidget(covariant QuizPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request != widget.request) {
      unawaited(
        _generationController.start(widget.request),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<QuizGenerationState>(
      quizGenerationControllerProvider,
      (previous, next) {
        if (next.unauthorized && !(previous?.unauthorized ?? false)) {
          widget.onUnauthorized?.call();
        }
      },
    );
    final generation = ref.watch(quizGenerationControllerProvider);
    final title = switch (generation.phase) {
      QuizGenerationPhase.complete => '练习题',
      QuizGenerationPhase.error => '生成失败',
      _ => '正在生成',
    };
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          unawaited(
            _generationController.cancel(),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              _GenerationStatus(state: generation),
              Expanded(
                child: _QuestionBody(
                  state: generation,
                  onRetry: _generationController.retry,
                  onAnswerQuestion: widget.onAnswerQuestion,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenerationStatus extends StatelessWidget {
  const _GenerationStatus({required this.state});

  final QuizGenerationState state;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final progress = state.requested > 0
        ? (state.questions.length / state.requested).clamp(0.0, 1.0)
        : null;
    final isError = state.phase == QuizGenerationPhase.error;
    return Semantics(
      liveRegion: true,
      label: state.message,
      child: ColoredBox(
        color: isError ? colors.errorContainer : colors.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  if (state.isLoading)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      isError
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      size: 20,
                      color: isError ? colors.error : colors.primary,
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      state.message.isEmpty ? '准备生成题目' : state.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (state.isLoading) ...<Widget>[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: progress),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestionBody extends StatelessWidget {
  const _QuestionBody({
    required this.state,
    required this.onRetry,
    required this.onAnswerQuestion,
  });

  final QuizGenerationState state;
  final VoidCallback onRetry;
  final ValueChanged<QuizQuestion>? onAnswerQuestion;

  @override
  Widget build(BuildContext context) {
    if (state.questions.isEmpty) {
      if (state.phase == QuizGenerationPhase.error) {
        return _QuizMessage(
          icon: Icons.cloud_off_outlined,
          title: '生成失败',
          message: state.message,
          actionLabel: '重新生成',
          onAction: onRetry,
        );
      }
      if (state.phase == QuizGenerationPhase.complete) {
        return _QuizMessage(
          icon: Icons.inbox_outlined,
          title: '没有生成题目',
          message: '可以返回调整知识点、题型或难度后再试。',
          actionLabel: '再试一次',
          onAction: onRetry,
        );
      }
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('第一道题生成后会立即显示在这里。'),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: state.questions.length +
          (state.phase == QuizGenerationPhase.error ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        if (index == state.questions.length) {
          return _PartialFailureCard(message: state.message, onRetry: onRetry);
        }
        return QuizQuestionCard(
          index: index,
          question: state.questions[index],
          onAnswer: onAnswerQuestion == null
              ? null
              : () => onAnswerQuestion!(state.questions[index]),
        );
      },
    );
  }
}

class QuizQuestionCard extends StatefulWidget {
  const QuizQuestionCard({
    super.key,
    required this.index,
    required this.question,
    this.onAnswer,
  });

  final int index;
  final QuizQuestion question;
  final VoidCallback? onAnswer;

  @override
  State<QuizQuestionCard> createState() => _QuizQuestionCardState();
}

class _QuizQuestionCardState extends State<QuizQuestionCard> {
  bool _showReference = false;

  @override
  Widget build(BuildContext context) {
    final question = widget.question;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  '第 ${widget.index + 1} 题',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Spacer(),
                if (question.difficulty.isNotEmpty)
                  _QuestionTag(label: _difficultyLabel(question.difficulty)),
                if (question.questionType.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 6),
                  _QuestionTag(label: _typeLabel(question.questionType)),
                ],
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              question.question,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(height: 1.5),
            ),
            if (question.options.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              ...question.options.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(width: 28, child: Text('${entry.key}.')),
                      Expanded(child: SelectableText(entry.value)),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _showReference = !_showReference),
                  icon: Icon(
                    _showReference ? Icons.visibility_off : Icons.visibility,
                  ),
                  label: Text(_showReference ? '隐藏参考答案' : '查看参考答案'),
                ),
                if (widget.onAnswer != null)
                  FilledButton.icon(
                    onPressed: widget.onAnswer,
                    icon: const Icon(Icons.mic_none),
                    label: const Text('开始作答'),
                  ),
              ],
            ),
            if (_showReference) ...<Widget>[
              const Divider(height: 28),
              Text('参考答案', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              SelectableText(
                question.correctAnswer.isEmpty
                    ? '暂无参考答案'
                    : question.correctAnswer,
              ),
              if (question.explanation.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text('解析', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                SelectableText(question.explanation),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static String _difficultyLabel(String value) => switch (value) {
        'easy' => '简单',
        'medium' => '中等',
        'hard' => '困难',
        _ => value,
      };

  static String _typeLabel(String value) => switch (value) {
        'choice' => '选择题',
        'concept' => '概念题',
        'fill_in_blank' => '填空题',
        'short_answer' => '简答题',
        'written' => '解答题',
        'coding' => '编程题',
        _ => value,
      };
}

class _QuestionTag extends StatelessWidget {
  const _QuestionTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: colors.onSecondaryContainer),
        ),
      ),
    );
  }
}

class _PartialFailureCard extends StatelessWidget {
  const _PartialFailureCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              const Icon(Icons.warning_amber_rounded),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
              TextButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      );
}

class _QuizMessage extends StatelessWidget {
  const _QuizMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: <Widget>[
              Icon(icon,
                  size: 52, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      );
}
