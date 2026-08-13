import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/judge_ws.dart';
import '../../../app/theme.dart';
import '../../../models/judge_result.dart';
import '../../../models/chat_message.dart';
import '../../../models/quiz_question.dart';
import '../../../widgets/rich_markdown.dart';
import '../../../widgets/streaming_text.dart';
import '../../auth/auth_controller.dart';

class InlineQuizCard extends ConsumerStatefulWidget {
  const InlineQuizCard({
    super.key,
    required this.questionNumber,
    required this.question,
    required this.onUnauthorized,
    required this.answerState,
    required this.onStateChanged,
    this.language = 'zh',
  });

  final int questionNumber;
  final QuizQuestion question;
  final VoidCallback onUnauthorized;
  final QuizAnswerState answerState;
  final ValueChanged<QuizAnswerState> onStateChanged;
  final String language;

  @override
  ConsumerState<InlineQuizCard> createState() => _InlineQuizCardState();
}

class _InlineQuizCardState extends ConsumerState<InlineQuizCard> {
  late final TextEditingController _answerController;
  JudgeWsClient? _judgeClient;
  StreamSubscription<JudgeEvent>? _judgeSubscription;
  late bool _judging;
  bool _showAnswer = false;
  // For choice/concept: the chosen option key ("A"/…) or "true"/"false".
  late String _selected;
  // True once an auto-gradable answer has been submitted (locks input and
  // reveals local pass/fail feedback), mirroring the web QuizViewer.
  late bool _submitted;
  late String _judgeText;
  String? _status;
  late String? _error;
  late JudgeResult? _result;

  @override
  void initState() {
    super.initState();
    _answerController = TextEditingController(text: widget.answerState.answer);
    // A card owns its judge socket. If it was evicted while judging, that
    // socket was cancelled in dispose and must not restore a stuck busy state.
    _judging = false;
    _selected = widget.answerState.selected;
    _submitted = widget.answerState.submitted;
    _judgeText = widget.answerState.judgeText;
    _error = widget.answerState.error;
    _result = widget.answerState.result;
  }

  void _notifyState() {
    widget.onStateChanged(
      QuizAnswerState(
        answer: _answerController.text,
        selected: _selected,
        submitted: _submitted,
        judging: _judging,
        judgeText: _judgeText,
        result: _result,
        error: _error,
      ),
    );
  }

  JudgeWsClient _newJudgeClient() {
    final session = ref.read(authControllerProvider).requireValue!;
    return JudgeWsClient.fromBaseUri(
      baseUri: Uri.parse(session.baseUrl),
      token: session.accessToken ?? '',
    );
  }

  Future<void> _judge() async {
    final answer = _answerForJudge().trim();
    if (answer.isEmpty) {
      setState(() => _error = '请先作答。');
      _notifyState();
      return;
    }
    await _judgeSubscription?.cancel();
    await _judgeClient?.cancel();
    final client = _newJudgeClient();
    _judgeClient = client;
    setState(() {
      _judging = true;
      _judgeText = '';
      _result = null;
      _error = null;
      _status = '正在连接评判服务…';
    });
    _notifyState();
    _judgeSubscription = client
        .judge(
      question: widget.question,
      userAnswer: answer,
      language: widget.language,
    )
        .listen(
      (event) {
        if (!mounted) return;
        switch (event.type) {
          case JudgeEventType.connecting:
            setState(() => _status = '正在连接评判服务…');
            break;
          case JudgeEventType.reconnecting:
            setState(() => _status = '连接中断，正在第 ${event.retryAttempt} 次重连…');
            break;
          case JudgeEventType.started:
            setState(() => _status = 'AI 正在评判…');
            break;
          case JudgeEventType.text:
            setState(() => _judgeText = event.accumulatedText);
            _notifyState();
            break;
          case JudgeEventType.done:
            final result =
                event.result ?? JudgeResult.fromText(event.accumulatedText);
            setState(() {
              _judgeText = result.text;
              _result = result;
              _judging = false;
              _status = '评判完成。';
            });
            _notifyState();
            break;
          case JudgeEventType.error:
            setState(() {
              _judgeText = event.accumulatedText;
              _judging = false;
              _error = event.content;
              _status = null;
            });
            _notifyState();
            if (event.unauthorized) widget.onUnauthorized();
            break;
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _judging = false;
          _error = '评判连接发生异常，请检查网络后重试。';
        });
        _notifyState();
      },
      onDone: () {
        if (mounted && _judging) {
          setState(() => _judging = false);
          _notifyState();
        }
      },
    );
  }

  @override
  void dispose() {
    _answerController.dispose();
    unawaited(_judgeSubscription?.cancel());
    unawaited(_judgeClient?.cancel());
    super.dispose();
  }

  /// The answer string handed to the AI judge, derived from whichever input
  /// the current question type uses.
  String _answerForJudge() {
    final q = widget.question;
    if (q.isMultipleChoice || q.questionType == 'concept') return _selected;
    return _answerController.text;
  }

  /// Select an option (choice key or "true"/"false"). Before submitting this
  /// just records the pick; after submitting the answer is locked.
  void _selectOption(String key) {
    if (_submitted) return;
    setState(() => _selected = key);
    _notifyState();
  }

  /// Submit an auto-gradable answer to reveal local pass/fail feedback.
  void _submitLocal() {
    setState(() {
      _submitted = true;
      _showAnswer = true;
    });
    _notifyState();
  }

  bool get _locallyCorrect => widget.question.isAnswerCorrectLocally(
        selected: _selected,
        typed: _answerController.text,
      );

  /// Visual state of choice option [key], reflecting selection and, once
  /// submitted, local correctness.
  _OptionState _optionStateFor(String key) {
    final selected = _selected == key;
    final revealed = _submitted || _result != null || _showAnswer;
    final isCorrect = key.toUpperCase() == widget.question.correctChoiceKey;
    if (revealed && isCorrect) return _OptionState.correct;
    if (revealed && selected && !isCorrect) return _OptionState.incorrect;
    if (selected) return _OptionState.selected;
    return _OptionState.idle;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final typeLabel = _typeLabel(widget.question.questionType);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  '第 ${widget.questionNumber} 题',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(typeLabel),
                  backgroundColor: colors.secondaryContainer,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: colors.onSecondaryContainer,
                  ),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                ),
                const Spacer(),
                if (widget.question.difficulty.isNotEmpty)
                  _DifficultyChip(difficulty: widget.question.difficulty),
              ],
            ),
            const SizedBox(height: 8),
            RichMarkdown(widget.question.question),
            const SizedBox(height: 12),
            ..._buildAnswerArea(context),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => setState(() => _showAnswer = !_showAnswer),
              icon: Icon(_showAnswer ? Icons.expand_less : Icons.expand_more),
              label: Text(_showAnswer ? '收起参考答案' : '查看参考答案与解析'),
            ),
            if (_showAnswer) ...<Widget>[
              const Divider(),
              Text('参考答案', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              SelectableText(
                widget.question.correctAnswer.isEmpty
                    ? '暂无参考答案'
                    : widget.question.correctAnswer,
              ),
              if (widget.question.explanation.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text('解析', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                RichMarkdown(widget.question.explanation),
              ],
            ],
            if (_status != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(_status!, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: colors.error)),
            ],
            if (_judgeText.isNotEmpty || _judging) ...<Widget>[
              const SizedBox(height: 16),
              Text('AI 评判', style: Theme.of(context).textTheme.titleSmall),
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

  /// The type-specific answer/input area. Auto-gradable types (choice, concept,
  /// fill_in_blank) submit for local pass/fail feedback and then offer an
  /// optional "问 AI"; open-ended types keep the AI-judge flow as the primary
  /// action. Mirrors the web `QuizViewer` per-type layout.
  List<Widget> _buildAnswerArea(BuildContext context) {
    final q = widget.question;
    return switch (q.questionType) {
      'choice' when q.options.isNotEmpty => _buildChoiceArea(context),
      'concept' => _buildConceptArea(context),
      'fill_in_blank' => _buildFillBlankArea(context),
      _ => _buildFreeTextArea(context),
    };
  }

  /// Choice: tap-to-select option tiles, then submit for local grading.
  List<Widget> _buildChoiceArea(BuildContext context) {
    return <Widget>[
      ...widget.question.options.entries.map(
        (option) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _OptionTile(
            optionKey: option.key,
            text: option.value,
            state: _optionStateFor(option.key),
            onTap: (_submitted || _judging)
                ? null
                : () => _selectOption(option.key),
          ),
        ),
      ),
      const SizedBox(height: 4),
      ..._buildAutoGradeControls(context),
    ];
  }

  /// Concept (true/false): two large side-by-side buttons.
  List<Widget> _buildConceptArea(BuildContext context) {
    return <Widget>[
      Row(
        children: <Widget>[
          Expanded(child: _buildTrueFalseButton('true', '正确')),
          const SizedBox(width: 8),
          Expanded(child: _buildTrueFalseButton('false', '错误')),
        ],
      ),
      const SizedBox(height: 8),
      ..._buildAutoGradeControls(context),
    ];
  }

  Widget _buildTrueFalseButton(String key, String label) {
    final colors = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    final selected = _selected == key;
    final revealed = _submitted;
    final isCorrect = key == widget.question.correctConceptAnswer;

    final (bg, border, fg) = () {
      if (revealed && isCorrect) {
        return (semantic.successBg, semantic.successFg, semantic.successFg);
      }
      if (revealed && selected && !isCorrect) {
        return (semantic.dangerBg, semantic.dangerFg, semantic.dangerFg);
      }
      if (selected) {
        return (
          colors.primary.withValues(alpha: 0.08),
          colors.primary,
          colors.onSurface,
        );
      }
      return (colors.surface, colors.outlineVariant, colors.onSurface);
    }();

    return InkWell(
      onTap: (_submitted || _judging) ? null : () => _selectOption(key),
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border, width: selected ? 1.5 : 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }

  /// Fill-in-the-blank: single-line input, then submit for local grading.
  List<Widget> _buildFillBlankArea(BuildContext context) {
    return <Widget>[
      TextField(
        controller: _answerController,
        enabled: !_submitted && !_judging,
        onChanged: (_) => _notifyState(),
        maxLines: 1,
        decoration: const InputDecoration(
          labelText: '你的答案',
          hintText: '填写答案',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      ..._buildAutoGradeControls(context),
    ];
  }

  /// Shared submit/feedback controls for the three auto-gradable types.
  List<Widget> _buildAutoGradeControls(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    final hasAnswer = widget.question.questionType == 'fill_in_blank'
        ? _answerController.text.trim().isNotEmpty
        : _selected.isNotEmpty;

    if (!_submitted) {
      return <Widget>[
        FilledButton.icon(
          onPressed: hasAnswer ? _submitLocal : null,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('提交'),
        ),
      ];
    }

    final correct = _locallyCorrect;
    return <Widget>[
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: correct ? semantic.successBg : semantic.dangerBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              correct ? Icons.check_circle : Icons.cancel,
              size: 18,
              color: correct ? semantic.successFg : semantic.dangerFg,
            ),
            const SizedBox(width: 8),
            Text(
              correct ? '回答正确' : '回答错误',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: correct ? semantic.successFg : semantic.dangerFg,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _judging ? null : _judge,
        icon: _judging
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.smart_toy_outlined, color: colors.primary),
        label: Text(_judging ? '评判中…' : '问 AI'),
      ),
    ];
  }

  /// Open-ended types (short_answer / written / coding): multi-line input and
  /// AI judging as the primary action. System keyboards can provide dictation.
  List<Widget> _buildFreeTextArea(BuildContext context) {
    final coding = widget.question.questionType == 'coding';
    final written = widget.question.questionType == 'written';
    return <Widget>[
      TextField(
        controller: _answerController,
        enabled: !_judging,
        onChanged: (_) => _notifyState(),
        minLines: coding ? 6 : (written ? 5 : 3),
        maxLines: coding ? 12 : 8,
        style: coding ? const TextStyle(fontFamily: 'monospace') : null,
        decoration: InputDecoration(
          labelText: '你的答案',
          hintText: coding ? '在此编写代码' : '输入答案',
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
        ),
      ),
      FilledButton.icon(
        onPressed: _judging ? null : _judge,
        icon: _judging
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.fact_check_outlined),
        label: Text(_judging ? '评判中…' : '提交 AI 评判'),
      ),
    ];
  }

  static String _typeLabel(String type) => switch (type) {
        'choice' => '选择题',
        'concept' => '概念题',
        'fill_in_blank' => '填空题',
        'short_answer' => '简答题',
        'written' => '论述题',
        'coding' => '编程题',
        _ => type.isEmpty ? '题目' : type,
      };
}

/// Small colored badge conveying question difficulty (green/amber/red).
class _DifficultyChip extends StatelessWidget {
  const _DifficultyChip({required this.difficulty});

  final String difficulty;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final colors = Theme.of(context).colorScheme;
    final (bg, fg, label) = switch (difficulty) {
      'easy' => (semantic.successBg, semantic.successFg, '简单'),
      'medium' => (semantic.warningBg, semantic.warningFg, '中等'),
      'hard' => (semantic.dangerBg, semantic.dangerFg, '困难'),
      _ => (
          colors.surfaceContainerHighest,
          colors.onSurfaceVariant,
          difficulty,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

/// Visual state of a tappable quiz option.
enum _OptionState { idle, selected, correct, incorrect }

/// A single tappable choice option, colored per [_OptionState].
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.optionKey,
    required this.text,
    required this.state,
    required this.onTap,
  });

  final String optionKey;
  final String text;
  final _OptionState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);

    final (bg, border, badgeBg, badgeFg) = switch (state) {
      _OptionState.idle => (
          semantic.quizOptionBackground,
          colors.outlineVariant,
          colors.primary.withValues(alpha: 0.12),
          colors.primary,
        ),
      _OptionState.selected => (
          colors.primary.withValues(alpha: 0.06),
          semantic.quizOptionSelectedBorder,
          colors.primary,
          colors.onPrimary,
        ),
      _OptionState.correct => (
          semantic.successBg,
          semantic.successFg,
          semantic.successFg,
          colors.surface,
        ),
      _OptionState.incorrect => (
          semantic.dangerBg,
          semantic.dangerFg,
          semantic.dangerFg,
          colors.surface,
        ),
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: border,
            width: state == _OptionState.idle ? 1 : 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badgeBg,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  optionKey,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: badgeFg,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RichMarkdown(
                  text,
                  variant: RichMarkdownVariant.compact,
                ),
              ),
              if (state == _OptionState.correct)
                Icon(Icons.check_circle, size: 18, color: semantic.successFg)
              else if (state == _OptionState.incorrect)
                Icon(Icons.cancel, size: 18, color: semantic.dangerFg),
            ],
          ),
        ),
      ),
    );
  }
}
