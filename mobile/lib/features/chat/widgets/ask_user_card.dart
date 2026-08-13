import 'package:flutter/material.dart';

/// Interactive card for the `ask_user` tool: the agent paused the turn and
/// waits for the learner's answers before continuing.
class AskUserCard extends StatefulWidget {
  const AskUserCard({
    super.key,
    required this.payload,
    required this.resolved,
    required this.submitting,
    required this.onSubmit,
  });

  /// Raw `ask_user` payload: `{intro, questions: [{id, prompt, header,
  /// multi_select, allow_free_text, options: [{label, description}]}]}`.
  final Map<String, dynamic> payload;
  final bool resolved;
  final bool submitting;
  final void Function(String text, List<Map<String, String>> answers) onSubmit;

  @override
  State<AskUserCard> createState() => _AskUserCardState();
}

class _AskUserQuestion {
  _AskUserQuestion({
    required this.id,
    required this.prompt,
    required this.header,
    required this.multiSelect,
    required this.allowFreeText,
    required this.options,
  });

  final String id;
  final String prompt;
  final String header;
  final bool multiSelect;
  final bool allowFreeText;
  final List<({String label, String description})> options;

  /// Short label for the tab, falling back to the prompt when no header.
  String get tabLabel => header.isNotEmpty ? header : prompt;
}

class _AskUserCardState extends State<AskUserCard> {
  late final List<_AskUserQuestion> _questions;
  final Map<String, Set<String>> _selected = <String, Set<String>>{};
  final Map<String, TextEditingController> _freeText =
      <String, TextEditingController>{};

  /// Index of the currently shown question when there is more than one; mirrors
  /// the web `InteractiveAskUserCard` tab navigation.
  int _activeIdx = 0;

  @override
  void initState() {
    super.initState();
    _questions = _parseQuestions(widget.payload);
    for (final question in _questions) {
      _selected[question.id] = <String>{};
      if (question.allowFreeText) {
        _freeText[question.id] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _freeText.values) {
      controller.dispose();
    }
    super.dispose();
  }

  static List<_AskUserQuestion> _parseQuestions(Map<String, dynamic> payload) {
    final rawQuestions = payload['questions'];
    final questions = <_AskUserQuestion>[];
    if (rawQuestions is! Iterable) return questions;
    var fallbackIndex = 0;
    for (final entry in rawQuestions) {
      if (entry is! Map) continue;
      fallbackIndex += 1;
      final options = <({String label, String description})>[];
      final rawOptions = entry['options'];
      if (rawOptions is Iterable) {
        for (final option in rawOptions) {
          if (option is! Map) continue;
          final label = option['label']?.toString().trim() ?? '';
          if (label.isEmpty) continue;
          options.add((
            label: label,
            description: option['description']?.toString().trim() ?? '',
          ));
        }
      }
      questions.add(_AskUserQuestion(
        id: entry['id']?.toString().trim().isNotEmpty == true
            ? entry['id'].toString().trim()
            : 'q$fallbackIndex',
        prompt: entry['prompt']?.toString() ?? '',
        header: entry['header']?.toString().trim() ?? '',
        multiSelect: entry['multi_select'] == true,
        allowFreeText: entry['allow_free_text'] != false,
        options: options,
      ));
    }
    return questions;
  }

  bool get _canSubmit {
    if (widget.resolved || widget.submitting) return false;
    for (final question in _questions) {
      if (!_isAnswered(question)) return false;
    }
    return _questions.isNotEmpty;
  }

  bool _isAnswered(_AskUserQuestion question) {
    final hasChoice = _selected[question.id]?.isNotEmpty == true;
    final hasFreeText = _freeText[question.id]?.text.trim().isNotEmpty == true;
    return hasChoice || hasFreeText;
  }

  void _submit() {
    final answers = <Map<String, String>>[];
    final parts = <String>[];
    for (final question in _questions) {
      final picked = (_selected[question.id] ?? const <String>{}).toList();
      final freeText = _freeText[question.id]?.text.trim() ?? '';
      final value = <String>[...picked, if (freeText.isNotEmpty) freeText]
          .join('; ');
      answers.add(<String, String>{'questionId': question.id, 'text': value});
      if (value.isNotEmpty) parts.add(value);
    }
    widget.onSubmit(parts.join('; '), answers);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final intro = widget.payload['intro']?.toString().trim() ?? '';
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.help_outline, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.resolved ? '已回答，继续生成中' : '请作答以继续',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          if (intro.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(intro, style: Theme.of(context).textTheme.bodyMedium),
          ],
          if (_questions.isNotEmpty) ..._buildPaged(context),
        ],
      ),
    );
  }

  /// Multi-question: horizontal tabs + one question at a time + bottom
  /// prev/next/submit nav. Single question: no tabs, direct submit. Mirrors
  /// the web `InteractiveAskUserCard`.
  List<Widget> _buildPaged(BuildContext context) {
    final multi = _questions.length > 1;
    final index = _activeIdx.clamp(0, _questions.length - 1);
    final question = _questions[index];

    return <Widget>[
      if (multi) ...<Widget>[
        const SizedBox(height: 12),
        _buildTabs(context, index),
      ],
      const SizedBox(height: 12),
      _buildQuestionBody(context, question),
      if (!widget.resolved) ...<Widget>[
        const SizedBox(height: 12),
        _buildNavBar(context, index: index, multi: multi),
      ],
    ];
  }

  Widget _buildTabs(BuildContext context, int index) {
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (var i = 0; i < _questions.length; i++)
          _buildTab(context, colors, i, i == index),
      ],
    );
  }

  Widget _buildTab(
    BuildContext context,
    ColorScheme colors,
    int i,
    bool active,
  ) {
    final question = _questions[i];
    final answered = _isAnswered(question);
    final label = question.tabLabel.trim();
    return InkWell(
      onTap: widget.submitting ? null : () => setState(() => _activeIdx = i),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? colors.primary.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? colors.primary : colors.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: answered
                    ? colors.primary
                    : colors.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: answered
                  ? Icon(Icons.check, size: 11, color: colors.onPrimary)
                  : Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
            ),
            if (label.isNotEmpty) ...<Widget>[
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: active ? colors.onSurface : colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionBody(BuildContext context, _AskUserQuestion question) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (question.prompt.trim().isNotEmpty)
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: question.prompt,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (question.multiSelect)
                  TextSpan(
                    text: '  可多选',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
              ],
            ),
          ),
        for (var i = 0; i < question.options.length; i++)
          _OptionTile(
            optionKey: _letterFor(i),
            label: question.options[i].label,
            description: question.options[i].description,
            selected: _selected[question.id]?.contains(
                  question.options[i].label,
                ) ==
                true,
            multiSelect: question.multiSelect,
            enabled: !widget.resolved && !widget.submitting,
            onTap: () => setState(() {
              final picked = _selected[question.id]!;
              final label = question.options[i].label;
              if (picked.contains(label)) {
                picked.remove(label);
              } else {
                if (!question.multiSelect) picked.clear();
                picked.add(label);
              }
            }),
          ),
        if (question.allowFreeText && !widget.resolved)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              controller: _freeText[question.id],
              enabled: !widget.submitting,
              minLines: 1,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: '其他 — 自定义回复…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNavBar(
    BuildContext context, {
    required int index,
    required bool multi,
  }) {
    final atFirst = index == 0;
    final atLast = index == _questions.length - 1;

    final Widget submitOrNext = (multi && !atLast)
        ? FilledButton.icon(
            onPressed:
                widget.submitting ? null : () => setState(() => _activeIdx++),
            icon: const Icon(Icons.chevron_right, size: 18),
            label: const Text('下一题'),
          )
        : FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: widget.submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('提交回答'),
          );

    return Row(
      children: <Widget>[
        if (multi && !atFirst)
          OutlinedButton.icon(
            onPressed:
                widget.submitting ? null : () => setState(() => _activeIdx--),
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('上一题'),
          ),
        const Spacer(),
        submitOrNext,
      ],
    );
  }

  static String _letterFor(int index) =>
      index < 26 ? String.fromCharCode(65 + index) : '${index + 1}';
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.optionKey,
    required this.label,
    required this.description,
    required this.selected,
    required this.multiSelect,
    required this.enabled,
    required this.onTap,
  });

  final String optionKey;
  final String label;
  final String description;
  final bool selected;
  final bool multiSelect;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? colors.primaryContainer : colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? colors.primary
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: (multiSelect && selected)
                    ? Icon(Icons.check, size: 14, color: colors.onPrimary)
                    : Text(
                        optionKey,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? colors.onPrimary
                              : colors.onSurfaceVariant,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: selected ? FontWeight.w600 : null,
                          ),
                    ),
                    if (description.isNotEmpty)
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
