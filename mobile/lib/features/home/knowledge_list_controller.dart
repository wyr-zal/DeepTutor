import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/knowledge_api.dart';
import '../../api/network_diagnostics.dart';
import '../../config/server_url.dart';
import '../../models/knowledge_base.dart';
import '../../services/auth_store.dart';
import '../../services/cache_namespace.dart';
import '../../services/knowledge_cache_store.dart';
import '../auth/auth_controller.dart';

final knowledgeRepositoryProvider = FutureProvider<KnowledgeRepository>((
  ref,
) async {
  final authStore = ref.watch(authStoreProvider);
  final baseUrl = (await authStore.readBaseUrl())?.trim();
  if (baseUrl == null || baseUrl.isEmpty) {
    throw const KnowledgeListException('尚未配置服务器，请重新登录。');
  }
  final client = ref.watch(apiClientProvider);
  return KnowledgeApi(
    loadJson: (path) async => (await client.get<dynamic>(baseUrl, path)).data,
  );
});

final knowledgeCacheStoreProvider =
    Provider.family<KnowledgeCacheStore, String>(
  (ref, namespace) => KnowledgeCacheStore(namespace: namespace),
);

enum KnowledgeListSource { remote, cache, empty }

class KnowledgeListState {
  const KnowledgeListState({
    required this.items,
    required this.source,
    this.lastSyncedAt,
    this.message,
    this.diagnosticDetails,
  });

  const KnowledgeListState.empty()
      : items = const <KnowledgeBase>[],
        source = KnowledgeListSource.empty,
        lastSyncedAt = null,
        message = null,
        diagnosticDetails = null;

  final List<KnowledgeBase> items;
  final KnowledgeListSource source;
  final DateTime? lastSyncedAt;
  final String? message;
  final String? diagnosticDetails;

  bool get fromCache => source == KnowledgeListSource.cache;
}

final knowledgeListControllerProvider =
    AsyncNotifierProvider<KnowledgeListController, KnowledgeListState>(
  KnowledgeListController.new,
);

class KnowledgeListController extends AsyncNotifier<KnowledgeListState> {
  @override
  Future<KnowledgeListState> build() async {
    return _load();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<KnowledgeListState>().copyWithPrevious(state);
    state = await AsyncValue.guard(() async {
      return _load();
    });
  }

  Future<KnowledgeListState> _load() async {
    final session = await ref.read(authBootstrapProvider.future).then(
          (_) => ref.read(authControllerProvider).valueOrNull,
        );
    if (session == null) {
      throw const KnowledgeListException('尚未建立本机会话。');
    }
    final cache = ref.read(
      knowledgeCacheStoreProvider(
        buildScopedCacheNamespace(
          serverUrl: session.baseUrl,
          userId: session.user.id,
        ),
      ),
    );
    final listUri = resolveServerUri(session.baseUrl, KnowledgeApi.listPath);
    try {
      final repository = await ref.read(knowledgeRepositoryProvider.future);
      final items = await repository.listKnowledgeBases();
      await cache.write(
        items: items,
        serverUrl: session.baseUrl,
        userId: session.user.id,
      );
      return KnowledgeListState(
        items: items,
        source: KnowledgeListSource.remote,
        lastSyncedAt: DateTime.now().toUtc(),
        diagnosticDetails: NetworkDiagnostics.describeSuccess(
          method: 'GET',
          uri: listUri,
          details: 'items=${items.length}',
        ),
      );
    } catch (error) {
      final diagnosticDetails = NetworkDiagnostics.describeObject(
        error,
        uri: listUri,
      );
      final cached = await cache.read();
      if (cached != null && cached.items.isNotEmpty) {
        return KnowledgeListState(
          items: cached.items,
          source: KnowledgeListSource.cache,
          lastSyncedAt: cached.lastSyncedAt,
          message: _readableError(error),
          diagnosticDetails: diagnosticDetails,
        );
      }
      return KnowledgeListState(
        items: const <KnowledgeBase>[],
        source: KnowledgeListSource.empty,
        message: _readableError(error),
        diagnosticDetails: diagnosticDetails,
      );
    }
  }

  static String _readableError(Object error) {
    if (error is KnowledgeListException) return error.message;
    return '服务器暂时不可用，当前显示本机缓存。';
  }
}

class KnowledgeListException implements Exception {
  const KnowledgeListException(this.message);

  final String message;

  @override
  String toString() => message;
}
