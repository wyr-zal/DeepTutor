import 'dart:io';

import 'package:deeptutor_mobile/models/judge_result.dart';
import 'package:deeptutor_mobile/models/quiz_attempt.dart';
import 'package:deeptutor_mobile/models/quiz_question.dart';
import 'package:deeptutor_mobile/services/attempt_history_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'deeptutor-history-test-',
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  QuizAttempt attempt(int minute) {
    final completedAt = DateTime.utc(2026, 7, 28, 10, minute);
    return QuizAttempt.create(
      question: const QuizQuestion(
        id: 'q-1',
        question: '2 + 2 = ?',
        questionType: 'short_answer',
        correctAnswer: '4',
        explanation: '加法。',
      ),
      userAnswer: '4',
      result: JudgeResult.fromText('✅ 正确', completedAt: completedAt),
      createdAt: completedAt,
    );
  }

  test('persists JSON attempts newest first', () async {
    final store = AttemptHistoryStore(directoryProvider: () async => directory);
    await store.save(attempt(1));
    await store.save(attempt(2));

    final restored = await store.readAll();
    expect(restored, hasLength(2));
    expect(restored.first.createdAt.minute, 2);
    expect(restored.first.question.question, '2 + 2 = ?');
    expect(restored.first.result.text, '✅ 正确');
  });

  test('caps local history to the configured bound', () async {
    final store = AttemptHistoryStore(
      directoryProvider: () async => directory,
      maxEntries: 1,
    );
    await store.save(attempt(1));
    await store.save(attempt(2));

    final restored = await store.readAll();
    expect(restored, hasLength(1));
    expect(restored.single.createdAt.minute, 2);
  });

  test('default store keeps the legacy file name', () async {
    final store = AttemptHistoryStore(directoryProvider: () async => directory);

    await store.save(attempt(1));

    final file = File(
      '${directory.path}${Platform.pathSeparator}quiz_attempts.json',
    );
    expect(await file.exists(), isTrue);
    expect(store.namespace, isNull);
  });

  test('scoped stores isolate users and server origins', () async {
    final first = AttemptHistoryStore.scoped(
      serverUrl: 'https://Tutor.Example.com/api',
      userId: 'learner-a',
      directoryProvider: () async => directory,
    );
    final sameOrigin = AttemptHistoryStore.scoped(
      serverUrl: 'https://tutor.example.com/other-prefix',
      userId: 'learner-a',
      directoryProvider: () async => directory,
    );
    final anotherUser = AttemptHistoryStore.scoped(
      serverUrl: 'https://tutor.example.com',
      userId: 'learner-b',
      directoryProvider: () async => directory,
    );
    final anotherServer = AttemptHistoryStore.scoped(
      serverUrl: 'https://other.example.com',
      userId: 'learner-a',
      directoryProvider: () async => directory,
    );

    expect(first.namespace, sameOrigin.namespace);
    expect(first.namespace, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(first.namespace, isNot(contains('learner')));
    expect(first.namespace, isNot(anotherUser.namespace));
    expect(first.namespace, isNot(anotherServer.namespace));

    await first.save(attempt(1));
    await anotherUser.save(attempt(2));
    expect((await first.readAll()).single.createdAt.minute, 1);
    expect((await anotherUser.readAll()).single.createdAt.minute, 2);
    expect(await anotherServer.readAll(), isEmpty);
  });

  test('namespace helper is stable and rejects invalid identity', () {
    expect(
      buildAttemptHistoryNamespace(
        serverUrl: 'https://tutor.example.com',
        userId: 'u1',
      ),
      '8de1f46a1b5e1945792c8b429436b4aebc3e34c93bdc112a35b51a1d403ec162',
    );
    expect(
      () => buildAttemptHistoryNamespace(
        serverUrl: 'https://tutor.example.com',
        userId: '   ',
      ),
      throwsArgumentError,
    );
    expect(
      () => AttemptHistoryStore(
        directoryProvider: () async => directory,
        namespace: '../other-user',
      ),
      throwsArgumentError,
    );
  });
}
