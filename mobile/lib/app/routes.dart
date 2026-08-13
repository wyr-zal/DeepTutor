import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/auth_api.dart';
import '../config/app_config.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/login_page.dart';
import '../features/chat/chat_shell_page.dart';
import '../models/auth_session.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, _) => _SessionGate(
          builder: (_) => const ChatShellPage(),
        ),
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      appBar: AppBar(title: const Text('无法打开页面')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            state.error?.toString() ?? '页面无法打开，请返回后重试。',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
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
    final config = ref.watch(appConnectionConfigProvider);

    // Bootstrap owns the full-page loading state. A form submission also sets
    // auth to loading, but keeping LoginPage mounted is essential so a 401 or
    // network error can be rendered next to the submitted credentials.
    if (bootstrap.isLoading) {
      return const _BootstrapPage();
    }

    if (auth.hasError) {
      return _BootstrapErrorPage(
        message: _readableBootstrapError(auth.error),
        onRetry: () => ref.invalidate(authBootstrapProvider),
        onEditServer:
            config.manualServerEntryEnabled && !config.hasFixedServerUrl
                ? () {
                    ref.read(authControllerProvider.notifier).forgetServer();
                  }
                : null,
      );
    }

    final session = auth.valueOrNull;
    if (session != null) return builder(session);
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
