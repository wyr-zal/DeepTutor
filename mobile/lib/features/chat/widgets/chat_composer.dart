import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/chat_message.dart';
import '../../../models/deep_question_config.dart';
import '../../home/knowledge_list_controller.dart';
import '../chat_controller.dart';
import '../composer_controller.dart';
import 'quiz_config_sheet.dart';

class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({super.key});

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final composer = ref.read(composerControllerProvider);
    final chat = ref.read(chatControllerProvider.notifier);
    if (composer.capability == ChatCapability.chat) {
      await chat.sendChat(text);
    } else {
      await chat.sendQuiz(
        text,
        composer.quizConfig,
        composer.selectedKnowledgeBases.toList(),
      );
    }
    if (!mounted || ref.read(chatControllerProvider).error != null) return;
    _controller.clear();
    _focusNode.requestFocus();
  }

  Future<void> _pickKnowledgeBases() async {
    final knowledge = ref.read(knowledgeListControllerProvider).valueOrNull;
    if (knowledge == null || knowledge.items.isEmpty) return;
    final current = ref.read(composerControllerProvider);
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      useSafeArea: true,
      builder: (context) {
        var draft = Set<String>.from(current.selectedKnowledgeBases);
        return StatefulBuilder(
          builder: (context, setModalState) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('选择知识库', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  current.capability == ChatCapability.deepQuestion
                      ? '出题流程当前优先使用第一个知识库。'
                      : '聊天可以同时参考多个知识库。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: knowledge.items.map((item) {
                      return CheckboxListTile(
                        value: draft.contains(item.name),
                        title: Text(item.name),
                        subtitle: item.documentCount == null
                            ? null
                            : Text('${item.documentCount} 个文档'),
                        onChanged: item.available
                            ? (checked) {
                                setModalState(() {
                                  checked == true
                                      ? draft.add(item.name)
                                      : draft.remove(item.name);
                                });
                              }
                            : null,
                      );
                    }).toList(),
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, draft),
                  child: const Text('完成'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null) {
      ref
          .read(composerControllerProvider.notifier)
          .replaceKnowledgeBases(selected);
    }
  }

  Future<void> _configureQuiz(DeepQuestionFormConfig config) async {
    final result = await showQuizConfigSheet(context, config);
    if (result != null) {
      ref.read(composerControllerProvider.notifier).updateQuizConfig(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final composer = ref.watch(composerControllerProvider);
    final chat = ref.watch(chatControllerProvider);
    final knowledge = ref.watch(knowledgeListControllerProvider).valueOrNull;
    final disabled = chat.isLoadingSession;
    final isQuiz = composer.capability == ChatCapability.deepQuestion;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      elevation: 4,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    ChoiceChip(
                      avatar: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: const Text('聊天'),
                      selected: !isQuiz,
                      onSelected: disabled
                          ? null
                          : (_) => ref
                              .read(composerControllerProvider.notifier)
                              .selectCapability(ChatCapability.chat),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      avatar: const Icon(Icons.quiz_outlined, size: 18),
                      label: const Text('出题'),
                      selected: isQuiz,
                      onSelected: disabled
                          ? null
                          : (_) => ref
                              .read(composerControllerProvider.notifier)
                              .selectCapability(ChatCapability.deepQuestion),
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      avatar:
                          const Icon(Icons.library_books_outlined, size: 18),
                      label: Text(
                        composer.selectedKnowledgeBases.isEmpty
                            ? '知识库'
                            : '知识库 ${composer.selectedKnowledgeBases.length}',
                      ),
                      onPressed: disabled || knowledge?.items.isEmpty != false
                          ? null
                          : _pickKnowledgeBases,
                    ),
                    if (isQuiz) ...<Widget>[
                      const SizedBox(width: 8),
                      ActionChip(
                        avatar: const Icon(Icons.tune, size: 18),
                        label: const Text('出题设置'),
                        onPressed: disabled
                            ? null
                            : () => _configureQuiz(composer.quizConfig),
                      ),
                    ],
                  ],
                ),
              ),
              if (isQuiz) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  summarizeQuizConfig(composer.quizConfig),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      enabled: !disabled,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: isQuiz ? '输入出题主题或要求' : '给 DeepTutor 发消息',
                        filled: true,
                        fillColor: colors.surfaceContainerLow,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (chat.isStreaming)
                    IconButton.filledTonal(
                      tooltip: '停止生成',
                      onPressed: ref.read(chatControllerProvider.notifier).stop,
                      icon: const Icon(Icons.stop_rounded),
                    )
                  else
                    IconButton.filled(
                      tooltip: isQuiz ? '开始出题' : '发送消息',
                      onPressed: disabled ? null : _send,
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
