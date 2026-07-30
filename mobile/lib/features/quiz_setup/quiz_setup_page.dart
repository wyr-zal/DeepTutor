import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/question_ws.dart';
import '../../models/knowledge_base.dart';
import '../auth/server_connection_controller.dart';

class QuizSetupPage extends ConsumerStatefulWidget {
  const QuizSetupPage({
    super.key,
    required this.knowledgeBase,
    required this.onStart,
  });

  final KnowledgeBase knowledgeBase;
  final ValueChanged<QuizGenerationRequest> onStart;

  @override
  ConsumerState<QuizSetupPage> createState() => _QuizSetupPageState();
}

class _QuizSetupPageState extends ConsumerState<QuizSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _knowledgePointController = TextEditingController();
  final _preferenceController = TextEditingController();
  String _questionType = 'choice';
  String _difficulty = 'medium';
  int _count = 3;

  @override
  void dispose() {
    _knowledgePointController.dispose();
    _preferenceController.dispose();
    super.dispose();
  }

  void _submit() {
    final connection = ref.read(serverConnectionControllerProvider).valueOrNull;
    if (connection?.online != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('生成题目需要联网，请先恢复服务器连接。')),
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    widget.onStart(
      QuizGenerationRequest(
        knowledgeBaseName: widget.knowledgeBase.name,
        knowledgePoint: _knowledgePointController.text.trim(),
        preference: _preferenceController.text.trim(),
        difficulty: _difficulty,
        questionType: _questionType,
        count: _count,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(serverConnectionControllerProvider);
    final snapshot = connection.valueOrNull;
    final canGenerate = snapshot?.online == true;
    return Scaffold(
      appBar: AppBar(title: const Text('配置练习')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: <Widget>[
              if (!canGenerate) ...<Widget>[
                _OnlineRequiredNotice(
                  loading: connection.isLoading,
                  message: snapshot?.message ?? '正在检查服务器连接…',
                  onRetry: () => ref
                      .read(serverConnectionControllerProvider.notifier)
                      .retry(),
                ),
                const SizedBox(height: 16),
              ],
              Text('知识库', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.library_books_outlined),
                ),
                child: Text(widget.knowledgeBase.name),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _knowledgePointController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: '知识点',
                  hintText: '例如：二次函数的图像与性质',
                  helperText: '描述越具体，题目越贴近你的学习目标。',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入要练习的知识点';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _questionType,
                decoration: const InputDecoration(
                  labelText: '题型',
                  border: OutlineInputBorder(),
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'choice', child: Text('选择题')),
                  DropdownMenuItem(value: 'concept', child: Text('概念题')),
                  DropdownMenuItem(value: 'fill_in_blank', child: Text('填空题')),
                  DropdownMenuItem(value: 'short_answer', child: Text('简答题')),
                  DropdownMenuItem(value: 'written', child: Text('解答题')),
                  DropdownMenuItem(value: 'coding', child: Text('编程题')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _questionType = value);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _difficulty,
                decoration: const InputDecoration(
                  labelText: '难度',
                  border: OutlineInputBorder(),
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'easy', child: Text('简单')),
                  DropdownMenuItem(value: 'medium', child: Text('中等')),
                  DropdownMenuItem(value: 'hard', child: Text('困难')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _difficulty = value);
                },
              ),
              const SizedBox(height: 20),
              Semantics(
                label: '题目数量，当前 $_count 道',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[const Text('题目数量'), Text('$_count 道')],
                    ),
                    Slider(
                      value: _count.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: '$_count 道',
                      onChanged: (value) =>
                          setState(() => _count = value.round()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _preferenceController,
                minLines: 2,
                maxLines: 4,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: '偏好（选填）',
                  hintText: '例如：结合生活场景，不要超纲',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: canGenerate ? _submit : null,
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(canGenerate ? '生成 $_count 道题' : '联网后可生成题目'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnlineRequiredNotice extends StatelessWidget {
  const _OnlineRequiredNotice({
    required this.loading,
    required this.message,
    required this.onRetry,
  });

  final bool loading;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (loading)
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.wifi_off_outlined, color: colors.outline),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '生成题目需要联网',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: loading ? null : onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
