import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../models/chat_message.dart';
import '../../../models/judge_result.dart';
import '../../../models/quiz_question.dart';
import 'inline_quiz_card.dart';

/// Paged container for a message's quiz questions. When there is more than one
/// question it shows a navigation bar (numbered chips + prev/next arrows) and a
/// progress bar, rendering one [InlineQuizCard] at a time — mirroring the web
/// `QuizViewer`. A single question renders the card directly with no chrome.
class QuizSection extends StatefulWidget {
  const QuizSection({
    super.key,
    required this.questions,
    required this.answerStates,
    required this.onUnauthorized,
    required this.onAnswerStateChanged,
  });

  final List<QuizQuestion> questions;
  final Map<String, QuizAnswerState> answerStates;
  final VoidCallback onUnauthorized;
  final void Function(String questionKey, QuizAnswerState answerState)
      onAnswerStateChanged;

  @override
  State<QuizSection> createState() => _QuizSectionState();
}

class _QuizSectionState extends State<QuizSection> {
  int _current = 0;

  @override
  void didUpdateWidget(covariant QuizSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the cursor in range if questions stream in or shrink.
    if (_current >= widget.questions.length) {
      _current = widget.questions.isEmpty ? 0 : widget.questions.length - 1;
    }
  }

  QuizAnswerState _stateFor(QuizQuestion q) =>
      widget.answerStates[q.deduplicationKey] ?? const QuizAnswerState();

  bool _isAnswered(QuizQuestion q) {
    final s = _stateFor(q);
    return s.result != null ||
        s.submitted ||
        s.answer.trim().isNotEmpty ||
        s.selected.trim().isNotEmpty;
  }

  /// Correctness for chip coloring: prefer the AI verdict when present,
  /// otherwise fall back to the local grade for submitted auto-gradable types.
  bool? _isCorrect(QuizQuestion q) {
    final s = _stateFor(q);
    if (s.result != null) {
      return s.result!.verdict == JudgeVerdict.correct;
    }
    if (s.submitted && q.isAutoGradable) {
      return q.isAnswerCorrectLocally(selected: s.selected, typed: s.answer);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) return const SizedBox.shrink();

    final multi = widget.questions.length > 1;
    final index = _current.clamp(0, widget.questions.length - 1);
    final question = widget.questions[index];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (multi) ...<Widget>[
          _QuizNavBar(
            questions: widget.questions,
            current: index,
            answeredKeys: <String>{
              for (final q in widget.questions)
                if (_isAnswered(q)) q.deduplicationKey,
            },
            correctKeys: <String>{
              for (final q in widget.questions)
                if (_isCorrect(q) == true) q.deduplicationKey,
            },
            incorrectKeys: <String>{
              for (final q in widget.questions)
                if (_isCorrect(q) == false) q.deduplicationKey,
            },
            onSelect: (i) => setState(() => _current = i),
            onPrev: index > 0 ? () => setState(() => _current = index - 1) : null,
            onNext: index < widget.questions.length - 1
                ? () => setState(() => _current = index + 1)
                : null,
          ),
          const SizedBox(height: 12),
        ],
        InlineQuizCard(
          key: ValueKey(question.deduplicationKey),
          questionNumber: index + 1,
          question: question,
          onUnauthorized: widget.onUnauthorized,
          answerState: _stateFor(question),
          onStateChanged: (answerState) =>
              widget.onAnswerStateChanged(question.deduplicationKey, answerState),
        ),
      ],
    );
  }
}

class _QuizNavBar extends StatelessWidget {
  const _QuizNavBar({
    required this.questions,
    required this.current,
    required this.answeredKeys,
    required this.correctKeys,
    required this.incorrectKeys,
    required this.onSelect,
    required this.onPrev,
    required this.onNext,
  });

  final List<QuizQuestion> questions;
  final int current;
  final Set<String> answeredKeys;
  final Set<String> correctKeys;
  final Set<String> incorrectKeys;
  final ValueChanged<int> onSelect;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final answeredCount = answeredKeys.length;
    final total = questions.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            _NavArrow(icon: Icons.chevron_left, onTap: onPrev),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    for (var i = 0; i < questions.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _NumberChip(
                          number: i + 1,
                          state: _chipState(questions[i].deduplicationKey, i),
                          onTap: () => onSelect(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            _NavArrow(icon: Icons.chevron_right, onTap: onNext),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : answeredCount / total,
            minHeight: 2,
            backgroundColor: colors.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }

  _ChipState _chipState(String key, int index) {
    if (index == current) return _ChipState.current;
    if (correctKeys.contains(key)) return _ChipState.correct;
    if (incorrectKeys.contains(key)) return _ChipState.incorrect;
    if (answeredKeys.contains(key)) return _ChipState.answered;
    return _ChipState.idle;
  }
}

class _NavArrow extends StatelessWidget {
  const _NavArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.outlineVariant),
          color: enabled ? colors.surface : colors.surfaceContainerLow,
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? colors.onSurface : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

enum _ChipState { current, correct, incorrect, answered, idle }

class _NumberChip extends StatelessWidget {
  const _NumberChip({
    required this.number,
    required this.state,
    required this.onTap,
  });

  final int number;
  final _ChipState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);

    final (bg, fg, showCheck) = switch (state) {
      _ChipState.current => (colors.primary, colors.onPrimary, false),
      _ChipState.correct => (semantic.successBg, semantic.successFg, false),
      _ChipState.incorrect => (semantic.dangerBg, semantic.dangerFg, false),
      _ChipState.answered => (
          colors.secondaryContainer,
          colors.onSecondaryContainer,
          true,
        ),
      _ChipState.idle => (
          colors.surfaceContainerHighest,
          colors.onSurfaceVariant,
          false,
        ),
    };

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: showCheck
            ? Icon(Icons.check, size: 14, color: fg)
            : Text(
                '$number',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
      ),
    );
  }
}
