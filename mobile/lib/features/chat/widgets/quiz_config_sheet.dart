import 'package:flutter/material.dart';

import '../../../models/deep_question_config.dart';

Future<DeepQuestionFormConfig?> showQuizConfigSheet(
  BuildContext context,
  DeepQuestionFormConfig initial,
) {
  return showModalBottomSheet<DeepQuestionFormConfig>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _QuizConfigSheet(initial: initial),
  );
}

class _QuizConfigSheet extends StatefulWidget {
  const _QuizConfigSheet({required this.initial});

  final DeepQuestionFormConfig initial;

  @override
  State<_QuizConfigSheet> createState() => _QuizConfigSheetState();
}

class _QuizConfigSheetState extends State<_QuizConfigSheet> {
  late DeepQuestionFormConfig _config = widget.initial;
  late final TextEditingController _paperController = TextEditingController(
    text: widget.initial.paperPath,
  );
  String? _error;

  @override
  void dispose() {
    _paperController.dispose();
    super.dispose();
  }

  void _apply() {
    final config = _config.copyWith(paperPath: _paperController.text.trim());
    if (config.mode == DeepQuestionMode.mimic && config.paperPath.isEmpty) {
      setState(() => _error = '请输入服务器上已经解析的试卷目录名。');
      return;
    }
    Navigator.pop(context, config);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '出题设置',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<DeepQuestionMode>(
              segments: const <ButtonSegment<DeepQuestionMode>>[
                ButtonSegment(
                  value: DeepQuestionMode.custom,
                  icon: Icon(Icons.tune),
                  label: Text('自定义'),
                ),
                ButtonSegment(
                  value: DeepQuestionMode.mimic,
                  icon: Icon(Icons.description_outlined),
                  label: Text('模仿试卷'),
                ),
              ],
              selected: <DeepQuestionMode>{_config.mode},
              onSelectionChanged: (selected) {
                setState(() {
                  _config = _config.copyWith(mode: selected.single);
                  _error = null;
                });
              },
            ),
            const SizedBox(height: 20),
            if (_config.mode == DeepQuestionMode.custom)
              _CustomQuizFields(
                config: _config,
                onChanged: (value) => setState(() => _config = value),
              )
            else
              _MimicQuizFields(
                config: _config,
                paperController: _paperController,
                onChanged: (value) => setState(() => _config = value),
              ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _apply,
              child: const Text('应用设置'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomQuizFields extends StatelessWidget {
  const _CustomQuizFields({required this.config, required this.onChanged});

  final DeepQuestionFormConfig config;
  final ValueChanged<DeepQuestionFormConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('题目数量：${config.numQuestions}'),
        Slider(
          value: config.numQuestions.toDouble(),
          min: 1,
          max: 50,
          divisions: 49,
          label: '${config.numQuestions}',
          onChanged: (value) => onChanged(
            config.copyWith(numQuestions: value.round()),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: config.difficulty,
          decoration: const InputDecoration(
            labelText: '难度',
            border: OutlineInputBorder(),
          ),
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem(value: 'auto', child: Text('自动')),
            DropdownMenuItem(value: 'easy', child: Text('简单')),
            DropdownMenuItem(value: 'medium', child: Text('中等')),
            DropdownMenuItem(value: 'hard', child: Text('困难')),
          ],
          onChanged: (value) {
            if (value != null) onChanged(config.copyWith(difficulty: value));
          },
        ),
        const SizedBox(height: 18),
        Text('题型（不选则自动）', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: kQuizQuestionTypes.map((type) {
            final selected = config.questionTypes.contains(type);
            return FilterChip(
              label: Text(kQuizQuestionTypeLabels[type] ?? type),
              selected: selected,
              onSelected: (_) {
                final types = List<String>.from(config.questionTypes);
                selected ? types.remove(type) : types.add(type);
                onChanged(
                  config.copyWith(
                    questionTypes: types,
                    perTypeCounts: const <String, int>{},
                  ),
                );
              },
            );
          }).toList(),
        ),
        if (config.questionTypes.length >= 2) ...<Widget>[
          const SizedBox(height: 16),
          Text('各题型数量', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          ...config.questionTypes.map((type) {
            final count = config.perTypeCounts[type] ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(kQuizQuestionTypeLabels[type] ?? type)),
                  IconButton.outlined(
                    tooltip: '减少${kQuizQuestionTypeLabels[type] ?? type}数量',
                    onPressed: count <= 0
                        ? null
                        : () {
                            final counts = Map<String, int>.from(
                              config.perTypeCounts,
                            );
                            counts[type] = count - 1;
                            onChanged(config.copyWith(perTypeCounts: counts));
                          },
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '$count',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: '增加${kQuizQuestionTypeLabels[type] ?? type}数量',
                    onPressed: count >= config.numQuestions
                        ? null
                        : () {
                            final counts = Map<String, int>.from(
                              config.perTypeCounts,
                            );
                            counts[type] = count + 1;
                            onChanged(config.copyWith(perTypeCounts: counts));
                          },
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            );
          }),
          Builder(
            builder: (context) {
              final total = config.questionTypes.fold<int>(
                0,
                (sum, type) => sum + (config.perTypeCounts[type] ?? 0),
              );
              final valid = total == config.numQuestions;
              return Text(
                valid
                    ? '分配合计 $total / ${config.numQuestions}，将按此数量出题。'
                    : '分配合计 $total / ${config.numQuestions}；合计不一致时由 AI 自动分配。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: valid
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                    ),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            '数量必须合计为 ${config.numQuestions}；全部为 0 可保持自动分配。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _MimicQuizFields extends StatelessWidget {
  const _MimicQuizFields({
    required this.config,
    required this.paperController,
    required this.onChanged,
  });

  final DeepQuestionFormConfig config;
  final TextEditingController paperController;
  final ValueChanged<DeepQuestionFormConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: paperController,
          decoration: const InputDecoration(
            labelText: '试卷目录名',
            hintText: '例如 2211asm1',
            helperText: '填写服务器上已经解析的试卷目录名；首版不上传 PDF。',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        Text('最多生成：${config.maxQuestions} 题'),
        Slider(
          value: config.maxQuestions.toDouble(),
          min: 1,
          max: 100,
          divisions: 99,
          label: '${config.maxQuestions}',
          onChanged: (value) => onChanged(
            config.copyWith(maxQuestions: value.round()),
          ),
        ),
      ],
    );
  }
}
