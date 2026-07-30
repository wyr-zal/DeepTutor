import 'dart:async';
import 'dart:io';

import 'package:deeptutor_mobile/api/attempt_api.dart';
import 'package:deeptutor_mobile/api/session_api.dart';
import 'package:deeptutor_mobile/features/history/attempt_history_page.dart';
import 'package:deeptutor_mobile/models/judge_result.dart';
import 'package:deeptutor_mobile/models/quiz_attempt.dart';
import 'package:deeptutor_mobile/models/quiz_question.dart';
import 'package:deeptutor_mobile/models/session_summary.dart';
import 'package:deeptutor_mobile/services/attempt_history_store.dart';
import 'package:deeptutor_mobile/services/session_summary_cache_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SessionRepository implements SessionRepository {
  _SessionRepository(this.load);

  final Future<List<SessionSummary>> Function() load;

  @override
  Future<List<SessionSummary>> listSessions({int limit = 50, int offset = 0}) {
    return load();
  }
}

class _AttemptStore extends AttemptHistoryStore {
  _AttemptStore(this.load)
      : super(directoryProvider: () async => Directory.systemTemp);

  final Future<List<QuizAttempt>> Function() load;

  @override
  Future<List<QuizAttempt>> readAll() => load();
}

class _AttemptRepository implements AttemptRepository {
  _AttemptRepository(this.load);

  final Future<List<QuizAttempt>> Function() load;

  @override
  Future<List<QuizAttempt>> listAttempts({int limit = 200}) => load();

  @override
  Future<void> saveAttempt(QuizAttempt attempt) async {}
}

class _SessionCacheStore extends SessionSummaryCacheStore {
  _SessionCacheStore({
    this.cached,
  }) : super(
          directoryProvider: () async => Directory.systemTemp,
          namespace: 'test-history-sessions',
          serverUrlHint: 'https://deeptutor.cliproxy.com.cn',
          userIdHint: 'local-admin',
        );

  final CachedSessionSummaries? cached;
  final List<List<SessionSummary>> writes = <List<SessionSummary>>[];

  @override
  Future<CachedSessionSummaries?> read() async => cached;

  @override
  Future<void> write({
    required List<SessionSummary> items,
    required String serverUrl,
    required String userId,
    DateTime? lastSyncedAt,
  }) async {
    writes.add(List<SessionSummary>.unmodifiable(items));
  }
}

void main() {
  late AttemptHistoryStore store;

  setUp(() {
    store = _AttemptStore(() async => const <QuizAttempt>[]);
  });

  Future<void> pumpPage(
    WidgetTester tester,
    SessionRepository repository, {
    AttemptRepository? attemptRepository,
    SessionSummaryCacheStore? sessionCacheStore,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AttemptHistoryPage(
          store: store,
          sessionRepository: repository,
          sessionCacheStore: sessionCacheStore,
          attemptRepository: attemptRepository,
        ),
      ),
    );
  }

  testWidgets('shows independent loading and empty states', (tester) async {
    final pending = Completer<List<SessionSummary>>();
    await pumpPage(tester, _SessionRepository(() => pending.future));

    expect(find.text('正在同步会话历史…'), findsOneWidget);

    pending.complete(const <SessionSummary>[]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('暂无服务端会话'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(find.text('暂无答题记录'), findsOneWidget);
  });

  testWidgets('server failure keeps the local section available', (
    tester,
  ) async {
    await pumpPage(
      tester,
      _SessionRepository(() => Future<List<SessionSummary>>.error('offline')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('服务端会话加载失败'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '重试同步'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    expect(find.text('暂无答题记录'), findsOneWidget);
  });

  testWidgets('renders server sessions together with remote attempts', (
    tester,
  ) async {
    final completedAt = DateTime.utc(2026, 7, 29, 10);
    final attempt = QuizAttempt.create(
      question: const QuizQuestion(
        id: 'q-1',
        question: '2 + 2 = ?',
        questionType: 'short_answer',
        options: <String, String>{},
        correctAnswer: '4',
        explanation: '加法。',
      ),
      userAnswer: '4',
      result: JudgeResult.fromText('正确', completedAt: completedAt),
      createdAt: completedAt,
    );
    const summary = SessionSummary(
      id: 'session-1',
      title: '二次函数复习',
      capability: 'deep_question',
      status: 'idle',
      messageCount: 4,
      lastMessage: '请再解释顶点式。',
      createdAt: null,
      updatedAt: null,
    );

    await pumpPage(
      tester,
      _SessionRepository(
        () async => const <SessionSummary>[summary],
      ),
      attemptRepository: _AttemptRepository(() async => <QuizAttempt>[attempt]),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('二次函数复习'), findsOneWidget);
    expect(find.text('请再解释顶点式。'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    expect(find.text('2 + 2 = ?'), findsOneWidget);
    expect(find.textContaining('推断：正确'), findsOneWidget);
  });

  testWidgets('falls back to cached sessions when server sessions fail', (
    tester,
  ) async {
    const cached = SessionSummary(
      id: 'cached-session',
      title: '缓存会话',
      capability: 'chat',
      status: 'idle',
      messageCount: 2,
      lastMessage: '这是上次同步的对话',
      createdAt: null,
      updatedAt: null,
    );

    await pumpPage(
      tester,
      _SessionRepository(() => Future<List<SessionSummary>>.error('offline')),
      sessionCacheStore: _SessionCacheStore(
        cached: const CachedSessionSummaries(
          items: <SessionSummary>[cached],
          lastSyncedAt: null,
          serverUrl: 'https://deeptutor.cliproxy.com.cn',
          userId: 'local-admin',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('缓存会话'), findsOneWidget);
    expect(find.text('这是上次同步的对话'), findsOneWidget);
    expect(find.text('服务端会话加载失败'), findsNothing);
  });

  testWidgets('falls back to local attempts when remote attempts fail', (
    tester,
  ) async {
    final completedAt = DateTime.utc(2026, 7, 29, 10);
    final attempt = QuizAttempt.create(
      question: const QuizQuestion(
        id: 'q-local',
        question: '本机缓存题目',
        questionType: 'short_answer',
        options: <String, String>{},
        correctAnswer: '答案',
        explanation: '',
      ),
      userAnswer: '答案',
      result: JudgeResult.fromText('正确', completedAt: completedAt),
      createdAt: completedAt,
    );
    store = _AttemptStore(() async => <QuizAttempt>[attempt]);

    await pumpPage(
      tester,
      _SessionRepository(() async => const <SessionSummary>[]),
      attemptRepository: _AttemptRepository(
        () => Future<List<QuizAttempt>>.error('offline'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    expect(find.text('本机缓存题目'), findsOneWidget);
  });
}
