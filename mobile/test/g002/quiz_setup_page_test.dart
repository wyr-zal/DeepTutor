import 'package:deeptutor_mobile/api/question_ws.dart';
import 'package:deeptutor_mobile/features/auth/server_connection_controller.dart';
import 'package:deeptutor_mobile/features/quiz_setup/quiz_setup_page.dart';
import 'package:deeptutor_mobile/models/knowledge_base.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _OfflineConnectionController extends ServerConnectionController {
  @override
  Future<ServerConnectionSnapshot> build() async {
    return const ServerConnectionSnapshot(
      status: ServerConnectionStatus.offline,
      message: '无法连接服务器，已切换为本机缓存浏览。',
    );
  }

  @override
  Future<void> retry() async {
    state = const AsyncData(
      ServerConnectionSnapshot(
        status: ServerConnectionStatus.offline,
        message: '无法连接服务器，已切换为本机缓存浏览。',
      ),
    );
  }
}

class _OnlineConnectionController extends ServerConnectionController {
  @override
  Future<ServerConnectionSnapshot> build() async {
    return const ServerConnectionSnapshot(
      status: ServerConnectionStatus.online,
      message: '服务器已连接，数据会自动同步。',
    );
  }
}

void main() {
  const knowledgeBase = KnowledgeBase(name: 'math');

  testWidgets('offline setup disables question generation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var started = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          serverConnectionControllerProvider.overrideWith(
            _OfflineConnectionController.new,
          ),
        ],
        child: MaterialApp(
          home: QuizSetupPage(
            knowledgeBase: knowledgeBase,
            onStart: (_) => started = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('生成题目需要联网'), findsOneWidget);
    expect(find.text('联网后可生成题目'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(started, isFalse);
  });

  testWidgets('online setup can start question generation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    QuizGenerationRequest? startedRequest;
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          serverConnectionControllerProvider.overrideWith(
            _OnlineConnectionController.new,
          ),
        ],
        child: MaterialApp(
          home: QuizSetupPage(
            knowledgeBase: knowledgeBase,
            onStart: (request) => startedRequest = request,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, '知识点'),
      '二次函数',
    );
    await tester.tap(find.widgetWithText(FilledButton, '生成 3 道题'));
    await tester.pumpAndSettle();

    expect(find.text('生成题目需要联网'), findsNothing);
    expect(startedRequest, isNotNull);
    expect(startedRequest?.knowledgeBaseName, 'math');
    expect(startedRequest?.knowledgePoint, '二次函数');
  });
}
