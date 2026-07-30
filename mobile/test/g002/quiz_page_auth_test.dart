import 'package:deeptutor_mobile/api/question_ws.dart';
import 'package:deeptutor_mobile/features/quiz/quiz_generation_controller.dart';
import 'package:deeptutor_mobile/features/quiz/quiz_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('quiz page forwards an expired websocket session to logout',
      (tester) async {
    var unauthorizedCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          questionGenerationGatewayProvider.overrideWith(
            (ref) async => const _UnauthorizedGateway(),
          ),
        ],
        child: MaterialApp(
          home: QuizPage(
            request: _request,
            onUnauthorized: () => unauthorizedCalls++,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(unauthorizedCalls, 1);
    expect(find.text('登录已失效，请重新登录。'), findsWidgets);
  });
}

const _request = QuizGenerationRequest(
  knowledgeBaseName: 'math',
  knowledgePoint: 'algebra',
  preference: '',
  difficulty: 'medium',
  questionType: 'choice',
  count: 1,
);

class _UnauthorizedGateway implements QuestionGenerationGateway {
  const _UnauthorizedGateway();

  @override
  Stream<QuestionStreamEvent> generate(QuizGenerationRequest request) =>
      Stream<QuestionStreamEvent>.error(
        const QuestionUnauthorizedException(),
      );
}
