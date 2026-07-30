import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/auth_api.dart';
import '../../api/network_diagnostics.dart';
import '../../config/server_url.dart';
import '../../models/auth_session.dart';
import 'auth_controller.dart';

enum ServerConnectionStatus {
  checking,
  online,
  offline,
  authMisconfigured,
}

class ServerConnectionSnapshot {
  const ServerConnectionSnapshot({
    required this.status,
    required this.message,
    this.checkedAt,
    this.diagnosticDetails,
  });

  const ServerConnectionSnapshot.checking()
      : status = ServerConnectionStatus.checking,
        message = '正在检查服务器连接…',
        checkedAt = null,
        diagnosticDetails = null;

  final ServerConnectionStatus status;
  final String message;
  final DateTime? checkedAt;
  final String? diagnosticDetails;

  bool get online => status == ServerConnectionStatus.online;
}

final serverConnectionControllerProvider =
    AsyncNotifierProvider<ServerConnectionController, ServerConnectionSnapshot>(
  ServerConnectionController.new,
);

class ServerConnectionController
    extends AsyncNotifier<ServerConnectionSnapshot> {
  AuthApi get _api => ref.read(authApiProvider);

  @override
  Future<ServerConnectionSnapshot> build() async {
    final session = await _session();
    if (session == null) {
      return const ServerConnectionSnapshot(
        status: ServerConnectionStatus.offline,
        message: '尚未建立本机会话。',
      );
    }
    return _check(session);
  }

  Future<void> retry() async {
    final session = await _session();
    if (session == null) {
      state = const AsyncData(
        ServerConnectionSnapshot(
          status: ServerConnectionStatus.offline,
          message: '尚未建立本机会话。',
        ),
      );
      return;
    }
    state = const AsyncLoading<ServerConnectionSnapshot>().copyWithPrevious(
      state,
    );
    state = AsyncData(await _check(session));
  }

  Future<AuthSession?> _session() async {
    final existing = ref.read(authControllerProvider).valueOrNull;
    if (existing != null) return existing;
    await ref.read(authBootstrapProvider.future);
    return ref.read(authControllerProvider).valueOrNull;
  }

  Future<ServerConnectionSnapshot> _check(AuthSession session) async {
    try {
      final status = await _api.status(session.baseUrl);
      final now = DateTime.now().toUtc();
      final uri = resolveServerUri(session.baseUrl, '/api/v1/auth/status');
      final diagnosticDetails = NetworkDiagnostics.describeSuccess(
        method: 'GET',
        uri: uri,
        statusCode: 200,
        details: 'enabled=${status.enabled}, user=${status.user?.id}',
      );
      if (status.enabled) {
        return ServerConnectionSnapshot(
          status: ServerConnectionStatus.authMisconfigured,
          message: '服务器已开启身份认证；固定单人版要求 auth.enabled=false。',
          checkedAt: now,
          diagnosticDetails: diagnosticDetails,
        );
      }
      return ServerConnectionSnapshot(
        status: ServerConnectionStatus.online,
        message: '服务器已连接，数据会自动同步。',
        checkedAt: now,
        diagnosticDetails: diagnosticDetails,
      );
    } on AuthApiException catch (error) {
      return ServerConnectionSnapshot(
        status: ServerConnectionStatus.offline,
        message: error.message,
        checkedAt: DateTime.now().toUtc(),
        diagnosticDetails: error.diagnosticDetails,
      );
    } catch (error) {
      return ServerConnectionSnapshot(
        status: ServerConnectionStatus.offline,
        message: '无法连接服务器，已切换为本机缓存浏览。',
        checkedAt: DateTime.now().toUtc(),
        diagnosticDetails: NetworkDiagnostics.describeObject(
          error,
          uri: resolveServerUri(session.baseUrl, '/api/v1/auth/status'),
        ),
      );
    }
  }
}
