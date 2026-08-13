import 'package:deeptutor_mobile/features/chat/widgets/inline_quiz_card.dart';
import 'package:deeptutor_mobile/models/chat_message.dart';
import 'package:deeptutor_mobile/models/quiz_question.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('open-ended quiz keeps typed answers in its persisted state', (
    tester,
  ) async {
    QuizAnswerState? capturedState;
    const question = QuizQuestion(
      id: 'written-1',
      question: '请说明牛顿第一定律。',
      questionType: 'written',
      correctAnswer: '',
      explanation: '',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: InlineQuizCard(
              questionNumber: 1,
              question: question,
              onUnauthorized: () {},
              answerState: const QuizAnswerState(),
              onStateChanged: (state) => capturedState = state,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '惯性定律');

    expect(capturedState?.answer, '惯性定律');
    expect(find.byIcon(Icons.mic_none), findsNothing);
    expect(find.textContaining('录音'), findsNothing);
  });
}
