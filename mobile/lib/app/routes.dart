import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../api/attempt_api.dart';
import '../api/auth_api.dart';
import '../api/judge_ws.dart';
import '../api/question_ws.dart';
import '../api/session_api.dart';
import '../api/voice_api.dart';
import '../config/app_config.dart';
import '../features/answer/quiz_answer_page.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/login_page.dart';
import '../features/history/attempt_history_page.dart';
import '../features/home/home_page.dart';
import '../features/quiz/quiz_page.dart';
import '../features/quiz_setup/quiz_setup_page.dart';
import '../models/auth_session.dart';
import '../models/knowledge_base.dart';
import '../models/quiz_question.dart';
import '../services/attempt_history_store.dart';
import '../services/session_summary_cache_store.dart';

final attemptHistoryStoreProvider =
    Provider.family<AttemptHistoryStore, String>(
  (ref, namespace) => AttemptHistoryStore(namespace: namespace),
);

final sessionSummaryCacheStoreProvider =
    Provider.family<SessionSummaryCacheStore, AuthSession>(
  (ref, session) => SessionSummaryCacheStore.scoped(
    serverUrl: session.baseUrl,
    userId: session.user.id,
  ),
);

String _historyNamespace(AuthSession session) {
  return buildAttemptHistoryNamespace(
    serverUrl: session.baseUrl,
    userId: session.user.id,
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, _) => _SessionGate(
          builder: (session) => HomePage(
            onSelectKnowledgeBase: (knowledgeBase) {
              context.push('/quiz/setup', extra: knowledgeBase);
            },
            onHistory: () => context.push('/history'),
            onLogout: () {
              ref.read(authControllerProvider.notifier).logout();
            },
          ),
        ),
      ),
      GoRoute(
        path: '/quiz/setup',
        builder: (context, state) {
          final knowledgeBase = state.extra;
          if (knowledgeBase is! KnowledgeBase) {
            return const _RouteErrorPage(message: '缺少知识库信息，请返回后重新选择。');
          }
          return _SessionGate(
            builder: (_) => QuizSetupPage(
              knowledgeBase: knowledgeBase,
              onStart: (request) {
                context.push('/quiz/generate', extra: request);
              },
            ),
          );
        },
      ),
      GoRoute(
        path: '/quiz/generate',
        builder: (context, state) {
          final request = state.extra;
          if (request is! QuizGenerationRequest) {
            return const _RouteErrorPage(message: '缺少出题参数，请返回后重新配置。');
          }
          return _SessionGate(
            builder: (_) => QuizPage(
              request: request,
              onUnauthorized: () {
                ref.read(authControllerProvider.notifier).logout();
              },
              onAnswerQuestion: (question) {
                context.push('/quiz/answer', extra: question);
              },
            ),
          );
        },
      ),
      GoRoute(
        path: '/quiz/answer',
        builder: (context, state) {
          final question = state.extra;
          if (question is! QuizQuestion) {
            return const _RouteErrorPage(message: '缺少题目信息，请返回后重新选择。');
          }
          return _SessionGate(
            builder: (session) {
              final token = session.accessToken ?? '';
              final baseUri = Uri.parse(session.baseUrl);
              return QuizAnswerPage(
                key: ValueKey(question.deduplicationKey),
                question: question,
                voiceApi: VoiceApi.fromBaseUri(
                  dio: ref.read(apiClientProvider).dio,
                  baseUri: baseUri,
                  token: token,
                ),
                judgeClient: JudgeWsClient.fromBaseUri(
                  baseUri: baseUri,
                  token: token,
                ),
                attemptRepository: AttemptApi.fromApiClient(
                  ref.read(apiClientProvider),
                  baseUrl: session.baseUrl,
                ),
                historyStore: ref.read(
                  attemptHistoryStoreProvider(_historyNamespace(session)),
                ),
                onUnauthorized: () {
                  ref.read(authControllerProvider.notifier).logout();
                },
              );
            },
          );
        },
      ),
      GoRoute(
        path: '/history',
        builder: (_, __) => _SessionGate(
          builder: (session) => AttemptHistoryPage(
            store: ref.read(
              attemptHistoryStoreProvider(_historyNamespace(session)),
            ),
            sessionRepository: SessionApi.fromApiClient(
              ref.read(apiClientProvider),
              baseUrl: session.baseUrl,
            ),
            sessionCacheStore: ref.read(
              sessionSummaryCacheStoreProvider(session),
            ),
            attemptRepository: AttemptApi.fromApiClient(
              ref.read(apiClientProvider),
              baseUrl: session.baseUrl,
            ),
          ),
        ),
      ),
    ],
    errorBuilder: (_, state) =>
        _RouteErrorPage(message: state.error?.toString() ?? '页面无法打开，请返回后重试。'),
  );
  ref.onDispose(router.dispose);
  return router;
});

class _SessionGate extends ConsumerWidget {
  const _SessionGate({required this.builder});

  final Widget Function(AuthSession session) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(authBootstrapProvider);
    final auth = ref.watch(authControllerProvider);

    // Bootstrap owns the full-page loading state. A form submission also sets
    // auth to loading, but keeping LoginPage mounted is essential so a 401 or
    // network error can be rendered next to the submitted credentials.
    if (bootstrap.isLoading) {
      return const _BootstrapPage();
    }

    if (auth.hasError) {
      final personalServerMode =
          ref.watch(appConnectionConfigProvider).personalServerMode;
      if (personalServerMode) {
        return _BootstrapErrorPage(
          message: _readableBootstrapError(auth.error),
          onRetry: () => ref.invalidate(authBootstrapProvider),
        );
      }
      return _BootstrapErrorPage(
        message: _readableBootstrapError(auth.error),
        onRetry: () => ref.invalidate(authBootstrapProvider),
        onEditServer: () {
          ref.read(authControllerProvider.notifier).forgetServer();
        },
      );
    }

    final session = auth.valueOrNull;
    if (session != null) return builder(session);
    if (ref.watch(appConnectionConfigProvider).personalServerMode) {
      return _BootstrapErrorPage(
        message: '固定服务器尚未建立会话，请检查服务器配置后重试。',
        onRetry: () => ref.invalidate(authBootstrapProvider),
      );
    }
    return const LoginPage();
  }

  static String _readableBootstrapError(Object? error) {
    if (error is AuthApiException) return error.message;
    if (error is FormatException) return error.message;
    return '无法连接固定服务器，请检查网络、HTTPS 证书和 DeepTutor 部署状态。';
  }
}

class _BootstrapPage extends StatelessWidget {
  const _BootstrapPage();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Semantics(
              liveRegion: true,
              label: '正在连接 DeepTutor',
              child: const CircularProgressIndicator(),
            ),
          ),
        ),
      );
}

class _BootstrapErrorPage extends StatelessWidget {
  const _BootstrapErrorPage({
    required this.message,
    required this.onRetry,
    this.onEditServer,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onEditServer;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.cloud_off_outlined, size: 52),
                  const SizedBox(height: 16),
                  Text(
                    '无法连接已保存的服务器',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                  if (onEditServer != null) ...<Widget>[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: onEditServer,
                      child: const Text('重新填写服务器地址'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}

class _RouteErrorPage extends StatelessWidget {
  const _RouteErrorPage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('无法打开页面')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ),
      );
}
