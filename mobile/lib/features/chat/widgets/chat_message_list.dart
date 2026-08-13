import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../../../app/theme.dart';
import '../../../models/chat_message.dart';
import '../../../models/think_segments.dart';
import '../../../widgets/rich_markdown.dart';
import '../../../widgets/streaming_text.dart';
import 'ask_user_card.dart';
import 'quiz_section.dart';
import 'thinking_card.dart';

class ChatMessageList extends StatefulWidget {
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.onUnauthorized,
    required this.onAnswerStateChanged,
    this.onSubmitUserReply,
  });

  final List<ChatMessage> messages;
  final VoidCallback onUnauthorized;
  final void Function(
    String messageId,
    String questionKey,
    QuizAnswerState answerState,
  ) onAnswerStateChanged;
  final void Function(
    String messageId,
    String text,
    List<Map<String, String>> answers,
  )? onSubmitUserReply;

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  static const double _latestPositionTolerance = 8;

  final ScrollController _scrollController = ScrollController();
  bool _followLatest = false;
  bool _userScrollInProgress = false;

  @override
  void didUpdateWidget(covariant ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.isEmpty) {
      _followLatest = false;
      _userScrollInProgress = false;
      return;
    }
    if (_followLatest &&
        _shouldScrollToEnd(oldWidget.messages, widget.messages)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
  }

  static bool _shouldScrollToEnd(
    List<ChatMessage> previous,
    List<ChatMessage> current,
  ) {
    if (previous.length != current.length) return true;
    if (previous.isEmpty) return false;
    final oldLast = previous.last;
    final newLast = current.last;
    return oldLast.id != newLast.id ||
        oldLast.textBuffer != newLast.textBuffer ||
        oldLast.thinkingBuffer != newLast.thinkingBuffer ||
        oldLast.quizQuestions.length != newLast.quizQuestions.length ||
        oldLast.streaming != newLast.streaming ||
        oldLast.error != newLast.error;
  }

  void _scrollToEnd() {
    if (!_followLatest || !_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userScrollInProgress = true;
      _followLatest = false;
    } else if (notification is UserScrollNotification &&
        _userScrollInProgress &&
        notification.direction == ScrollDirection.idle) {
      _followLatest = _isAtLatestPosition(notification.metrics);
      _userScrollInProgress = false;
    }
    return false;
  }

  static bool _isAtLatestPosition(ScrollMetrics metrics) =>
      metrics.extentAfter <= _latestPositionTolerance;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.messages.isEmpty) return const _EmptyChat();
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: ListView.builder(
        key: const ValueKey('chat-message-list'),
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
        itemCount: widget.messages.length,
        itemBuilder: (context, index) {
          final message = widget.messages[index];
          return _ChatMessageBubble(
            key: ValueKey(message.id),
            message: message,
            onUnauthorized: widget.onUnauthorized,
            onAnswerStateChanged: widget.onAnswerStateChanged,
            onSubmitUserReply: widget.onSubmitUserReply,
          );
        },
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Icon(
                  Icons.auto_awesome_outlined,
                  size: 34,
                  color: colors.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '今天想学什么？',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '直接提问，或在输入框上方切换“出题”能力。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessageBubble extends StatelessWidget {
  const _ChatMessageBubble({
    super.key,
    required this.message,
    required this.onUnauthorized,
    required this.onAnswerStateChanged,
    this.onSubmitUserReply,
  });

  final ChatMessage message;
  final VoidCallback onUnauthorized;
  final void Function(
    String messageId,
    String questionKey,
    QuizAnswerState answerState,
  ) onAnswerStateChanged;
  final void Function(
    String messageId,
    String text,
    List<Map<String, String>> answers,
  )? onSubmitUserReply;

  @override
  Widget build(BuildContext context) {
    final user = message.role == ChatRole.user;
    final colors = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);

    // Split any inline <think>...</think> out of the assistant body, and merge
    // it with thinking that arrived as dedicated events.
    final split = user ? null : splitThinking(message.textBuffer);
    final bodyText = user ? message.textBuffer : (split?.body ?? '');
    final inlineThinking = split?.thinking ?? '';
    final thinkingText = <String>[
      if (message.thinkingBuffer.trim().isNotEmpty)
        message.thinkingBuffer.trim(),
      if (inlineThinking.trim().isNotEmpty) inlineThinking.trim(),
    ].join('\n\n');
    final thinkingClosed =
        message.thinkingClosed && (split?.thinkingClosed ?? true);
    final showThinking = !user && thinkingText.isNotEmpty;

    final hasText = bodyText.trim().isNotEmpty || message.streaming;
    final content = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * (user ? 0.82 : 0.92),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: user ? semantic.userBubble : colors.surfaceContainerLow,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(user ? 18 : 4),
            bottomRight: Radius.circular(user ? 4 : 18),
          ),
          border:
              user ? null : Border.all(color: semantic.assistantBubbleBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (showThinking)
                ThinkingCard(
                  content: thinkingText,
                  closed: thinkingClosed,
                ),
              if (hasText)
                if (user)
                  RichMarkdown(bodyText)
                else
                  StreamingText(
                    text: bodyText,
                    isStreaming: message.streaming,
                    emptyStreamingText: showThinking ? '' : 'DeepTutor 正在思考…',
                    emptyText: '',
                    streamingSemanticsLabel: 'AI 回复正在生成',
                    completedSemanticsLabel: 'AI 回复',
                  ),
              if (message.askUser != null)
                AskUserCard(
                  key: ValueKey('ask-user-${message.id}'),
                  payload: message.askUser!,
                  resolved: message.askUserResolved,
                  submitting: message.askUserSubmitting,
                  onSubmit: (text, answers) =>
                      onSubmitUserReply?.call(message.id, text, answers),
                ),
              if (message.quizQuestions.isNotEmpty) ...<Widget>[
                if (hasText) const SizedBox(height: 14),
                QuizSection(
                  questions: message.quizQuestions,
                  answerStates: message.answerStates,
                  onUnauthorized: onUnauthorized,
                  onAnswerStateChanged: (questionKey, answerState) =>
                      onAnswerStateChanged(
                    message.id,
                    questionKey,
                    answerState,
                  ),
                ),
              ],
              if (message.error != null) ...<Widget>[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.error_outline, size: 18, color: colors.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message.error!,
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Align(
        alignment: user ? Alignment.centerRight : Alignment.centerLeft,
        child: content,
      ),
    );
  }
}
