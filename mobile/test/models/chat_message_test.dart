import 'package:deeptutor_mobile/models/chat_message.dart';
import 'package:deeptutor_mobile/models/judge_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copyWith retains independent per-question answer state', () {
    const first = QuizAnswerState(answer: 'A');
    final second = QuizAnswerState(
      answer: 'B',
      judgeText: '回答正确',
      result: JudgeResult.fromText('正确：回答完整。'),
    );
    const message = ChatMessage(
      id: 'assistant-1',
      role: ChatRole.assistant,
      textBuffer: '',
    );

    final withFirst = message.copyWith(
      answerStates: const <String, QuizAnswerState>{'question-1': first},
    );
    final withSecond = withFirst.copyWith(
      answerStates: <String, QuizAnswerState>{
        ...withFirst.answerStates,
        'question-2': second,
      },
    );

    expect(withSecond.answerStates['question-1']?.answer, 'A');
    expect(withSecond.answerStates['question-2']?.answer, 'B');
    expect(
        withSecond.answerStates['question-2']?.result?.verdict.name, 'correct');
    expect(message.answerStates, isEmpty);
  });
}
