import 'package:deeptutor_mobile/api/question_ws.dart';
import 'package:deeptutor_mobile/features/quiz/quiz_generation_controller.dart';
import 'package:deeptutor_mobile/models/quiz_question.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const request = QuizGenerationRequest(
    knowledgeBaseName: 'math',
    knowledgePoint: 'algebra',
    preference: '',
    difficulty: 'medium',
    questionType: 'choice',
    count: 2,
  );
  const question = QuizQuestion(
    id: 'q-1',
    question: '2 + 2 = ?',
    questionType: 'choice',
    options: <String, String>{'A': '3', 'B': '4'},
    correctAnswer: '4',
    explanation: 'Basic addition.',
  );

  test(
    'streams questions, deduplicates result copies, and completes',
    () async {
      final gateway = _FakeGateway(<QuestionStreamEvent>[
        const QuestionStreamEvent(type: QuestionStreamEventType.connected),
        const QuestionStreamEvent(
          type: QuestionStreamEventType.taskId,
          taskId: 'task-1',
        ),
        const QuestionStreamEvent(
          type: QuestionStreamEventType.question,
          question: question,
        ),
        const QuestionStreamEvent(
          type: QuestionStreamEventType.question,
          question: question,
        ),
        const QuestionStreamEvent(
          type: QuestionStreamEventType.batchSummary,
          requested: 2,
          completed: 1,
          failed: 1,
        ),
        const QuestionStreamEvent(type: QuestionStreamEventType.complete),
      ]);
      final container = ProviderContainer(
        overrides: [
          questionGenerationGatewayProvider.overrideWith(
            (ref) async => gateway,
          ),
        ],
      );
      addTearDown(container.dispose);
      final keepAlive = container.listen(
        quizGenerationControllerProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(keepAlive.close);

      await container
          .read(quizGenerationControllerProvider.notifier)
          .start(request);
      final state = container.read(quizGenerationControllerProvider);

      expect(state.phase, QuizGenerationPhase.complete);
      expect(state.isLoading, isFalse);
      expect(state.taskId, 'task-1');
      expect(state.questions, hasLength(1));
      expect(state.failed, 1);
    },
  );

  test('keeps already streamed questions visible after an error', () async {
    final gateway = _FakeGateway(<QuestionStreamEvent>[
      const QuestionStreamEvent(
        type: QuestionStreamEventType.question,
        question: question,
      ),
      const QuestionStreamEvent(
        type: QuestionStreamEventType.error,
        message: 'provider unavailable',
      ),
    ]);
    final container = ProviderContainer(
      overrides: [
        questionGenerationGatewayProvider.overrideWith((ref) async => gateway),
      ],
    );
    addTearDown(container.dispose);
    final keepAlive = container.listen(
      quizGenerationControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(keepAlive.close);

    await container
        .read(quizGenerationControllerProvider.notifier)
        .start(request);
    final state = container.read(quizGenerationControllerProvider);

    expect(state.phase, QuizGenerationPhase.error);
    expect(state.questions, hasLength(1));
    expect(state.message, 'provider unavailable');
  });

  test('marks an expired websocket session as unauthorized', () async {
    final container = ProviderContainer(
      overrides: [
        questionGenerationGatewayProvider.overrideWith(
          (ref) async => const _ErrorGateway(QuestionUnauthorizedException()),
        ),
      ],
    );
    addTearDown(container.dispose);
    final keepAlive = container.listen(
      quizGenerationControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(keepAlive.close);

    await container
        .read(quizGenerationControllerProvider.notifier)
        .start(request);
    final state = container.read(quizGenerationControllerProvider);

    expect(state.phase, QuizGenerationPhase.error);
    expect(state.unauthorized, isTrue);
    expect(state.message, '登录已失效，请重新登录。');
  });
}

class _FakeGateway implements QuestionGenerationGateway {
  const _FakeGateway(this.events);

  final List<QuestionStreamEvent> events;

  @override
  Stream<QuestionStreamEvent> generate(QuizGenerationRequest request) =>
      Stream<QuestionStreamEvent>.fromIterable(events);
}

class _ErrorGateway implements QuestionGenerationGateway {
  const _ErrorGateway(this.error);

  final Object error;

  @override
  Stream<QuestionStreamEvent> generate(QuizGenerationRequest request) =>
      Stream<QuestionStreamEvent>.error(error);
}
