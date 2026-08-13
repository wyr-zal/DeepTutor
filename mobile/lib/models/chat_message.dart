import 'judge_result.dart';
import 'quiz_question.dart';

enum ChatRole { user, assistant }

enum ChatCapability { chat, deepQuestion }

class QuizAnswerState {
  const QuizAnswerState({
    this.answer = '',
    this.selected = '',
    this.submitted = false,
    this.judging = false,
    this.judgeText = '',
    this.result,
    this.error,
  });

  final String answer;

  /// The chosen option key ("A"/"B"/…) for choice questions, or "true"/"false"
  /// for concept (true/false) questions. Empty for free-text types.
  final String selected;

  /// True once the learner has submitted an auto-gradable answer, which
  /// reveals the local pass/fail feedback — mirrors the web `QuizViewer`.
  final bool submitted;

  final bool judging;
  final String judgeText;
  final JudgeResult? result;
  final String? error;

  factory QuizAnswerState.fromJson(Map<String, dynamic> json) =>
      QuizAnswerState(
        answer: json['answer']?.toString() ?? '',
        selected: json['selected']?.toString() ?? '',
        submitted: json['submitted'] == true,
        judging: json['judging'] == true,
        judgeText: json['judge_text']?.toString() ?? '',
        result: json['result'] is Map
            ? JudgeResult.fromJson(
                (json['result'] as Map)
                    .map((key, value) => MapEntry(key.toString(), value)),
              )
            : null,
        error: json['error']?.toString(),
      );

  QuizAnswerState copyWith({
    String? answer,
    String? selected,
    bool? submitted,
    bool? judging,
    String? judgeText,
    JudgeResult? result,
    bool clearResult = false,
    String? error,
    bool clearError = false,
  }) =>
      QuizAnswerState(
        answer: answer ?? this.answer,
        selected: selected ?? this.selected,
        submitted: submitted ?? this.submitted,
        judging: judging ?? this.judging,
        judgeText: judgeText ?? this.judgeText,
        result: clearResult ? null : result ?? this.result,
        error: clearError ? null : error ?? this.error,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'answer': answer,
        if (selected.isNotEmpty) 'selected': selected,
        'submitted': submitted,
        'judging': judging,
        'judge_text': judgeText,
        if (result != null) 'result': result!.toJson(),
        if (error != null) 'error': error,
      };
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.textBuffer,
    this.capability = ChatCapability.chat,
    this.quizQuestions = const <QuizQuestion>[],
    this.quizMeta,
    this.streaming = false,
    this.error,
    this.answerStates = const <String, QuizAnswerState>{},
    this.thinkingBuffer = '',
    this.thinkingClosed = false,
    this.askUser,
    this.askUserToolCallId,
    this.askUserResolved = false,
    this.askUserSubmitting = false,
  });

  final String id;
  final ChatRole role;
  final String textBuffer;
  final ChatCapability capability;
  final List<QuizQuestion> quizQuestions;
  final Map<String, dynamic>? quizMeta;
  final bool streaming;
  final String? error;
  final Map<String, QuizAnswerState> answerStates;

  /// Accumulated model "thinking" text (from `thinking` events and inline
  /// `<think>...</think>` segments). Rendered in a collapsible card.
  final String thinkingBuffer;

  /// True once the model has finished emitting its thinking (a closing
  /// `</think>` was seen or the first content/result arrived).
  final bool thinkingClosed;

  /// Pending clarification request from the `ask_user` tool
  /// (intro + questions with options), or null when none was asked.
  final Map<String, dynamic>? askUser;
  final String? askUserToolCallId;
  final bool askUserResolved;

  /// True while this device's answer is in flight (not persisted).
  final bool askUserSubmitting;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawQuestions = json['quiz_questions'];
    final rawAnswers = json['answer_states'];
    return ChatMessage(
      id: json['id']?.toString() ?? '',
      role: json['role'] == ChatRole.user.name
          ? ChatRole.user
          : ChatRole.assistant,
      textBuffer: json['text_buffer']?.toString() ?? '',
      capability: json['capability'] == ChatCapability.deepQuestion.name
          ? ChatCapability.deepQuestion
          : ChatCapability.chat,
      quizQuestions: List<QuizQuestion>.unmodifiable(
        (rawQuestions is Iterable ? rawQuestions : const <Object>[])
            .whereType<Map>()
            .map(
              (item) => QuizQuestion.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ),
            ),
      ),
      quizMeta: json['quiz_meta'] is Map
          ? (json['quiz_meta'] as Map)
              .map((key, value) => MapEntry(key.toString(), value))
          : null,
      streaming: json['streaming'] == true,
      error: json['error']?.toString(),
      answerStates: rawAnswers is Map
          ? rawAnswers.map(
              (key, value) => MapEntry(
                key.toString(),
                value is Map
                    ? QuizAnswerState.fromJson(
                        value.map(
                          (nestedKey, nestedValue) =>
                              MapEntry(nestedKey.toString(), nestedValue),
                        ),
                      )
                    : const QuizAnswerState(),
              ),
            )
          : const <String, QuizAnswerState>{},
      thinkingBuffer: json['thinking_buffer']?.toString() ?? '',
      thinkingClosed: json['thinking_closed'] == true,
      askUser: json['ask_user'] is Map
          ? (json['ask_user'] as Map)
              .map((key, value) => MapEntry(key.toString(), value))
          : null,
      askUserToolCallId: json['ask_user_tool_call_id']?.toString(),
      askUserResolved: json['ask_user_resolved'] == true,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'role': role.name,
        'text_buffer': textBuffer,
        'capability': capability.name,
        'quiz_questions': quizQuestions.map((item) => item.toJson()).toList(),
        if (quizMeta != null) 'quiz_meta': quizMeta,
        'streaming': streaming,
        if (error != null) 'error': error,
        'answer_states': answerStates.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
        'thinking_buffer': thinkingBuffer,
        'thinking_closed': thinkingClosed,
        if (askUser != null) 'ask_user': askUser,
        if (askUserToolCallId != null)
          'ask_user_tool_call_id': askUserToolCallId,
        'ask_user_resolved': askUserResolved,
      };

  ChatMessage copyWith({
    String? id,
    ChatRole? role,
    String? textBuffer,
    ChatCapability? capability,
    List<QuizQuestion>? quizQuestions,
    Map<String, dynamic>? quizMeta,
    bool clearQuizMeta = false,
    bool? streaming,
    String? error,
    bool clearError = false,
    Map<String, QuizAnswerState>? answerStates,
    String? thinkingBuffer,
    bool? thinkingClosed,
    Map<String, dynamic>? askUser,
    String? askUserToolCallId,
    bool? askUserResolved,
    bool? askUserSubmitting,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      textBuffer: textBuffer ?? this.textBuffer,
      capability: capability ?? this.capability,
      quizQuestions: quizQuestions ?? this.quizQuestions,
      quizMeta: clearQuizMeta ? null : quizMeta ?? this.quizMeta,
      streaming: streaming ?? this.streaming,
      error: clearError ? null : error ?? this.error,
      answerStates: answerStates ?? this.answerStates,
      thinkingBuffer: thinkingBuffer ?? this.thinkingBuffer,
      thinkingClosed: thinkingClosed ?? this.thinkingClosed,
      askUser: askUser ?? this.askUser,
      askUserToolCallId: askUserToolCallId ?? this.askUserToolCallId,
      askUserResolved: askUserResolved ?? this.askUserResolved,
      askUserSubmitting: askUserSubmitting ?? this.askUserSubmitting,
    );
  }
}
