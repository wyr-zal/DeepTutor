import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/session_api.dart';
import '../../models/auth_session.dart';
import '../../models/session_summary.dart';
import '../../services/local_chat_store.dart';
import '../auth/auth_controller.dart';
import 'local_chat_store_provider.dart';

final sessionApiProvider = Provider.family<SessionApi, AuthSession>(
  (ref, session) => SessionApi.fromApiClient(
    ref.watch(apiClientProvider),
    baseUrl: session.baseUrl,
  ),
);

final sessionListControllerProvider = AutoDisposeAsyncNotifierProvider<
    SessionListController, List<SessionSummary>>(
  SessionListController.new,
);

class SessionListController
    extends AutoDisposeAsyncNotifier<List<SessionSummary>> {
  AuthSession get _session => ref.read(authControllerProvider).requireValue!;

  SessionApi get _api => ref.read(sessionApiProvider(_session));

  LocalChatStore get _store => ref.read(localChatStoreProvider(_session));

  @override
  Future<List<SessionSummary>> build() async {
    final cached = await _store.readSummaries();
    if (cached.isNotEmpty) {
      state = AsyncData<List<SessionSummary>>(cached);
      unawaited(_syncQuietly());
      return cached;
    }
    return _syncWithFallback();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<List<SessionSummary>>().copyWithPrevious(state);
    state = await AsyncValue.guard(_syncWithFallback);
  }

  Future<void> rename(String id, String title) async {
    await _api.renameSession(id, title);
    final current = state.valueOrNull ?? const <SessionSummary>[];
    state = AsyncData<List<SessionSummary>>(
      current
          .map(
            (session) => session.id == id
                ? SessionSummary(
                    id: session.id,
                    title: title.trim(),
                    capability: session.capability,
                    status: session.status,
                    messageCount: session.messageCount,
                    lastMessage: session.lastMessage,
                    createdAt: session.createdAt,
                    updatedAt: session.updatedAt,
                    revision: session.revision,
                  )
                : session,
          )
          .toList(growable: false),
    );
    await _store.applySync(
      SessionSyncPage(
        cursor: await _store.readCursor(),
        sessions: state.valueOrNull ?? const <SessionSummary>[],
        deletedSessionIds: const <String>[],
        hasMore: false,
        incremental: true,
      ),
    );
  }

  Future<void> remove(String id) async {
    await _api.deleteSession(id);
    final current = state.valueOrNull ?? const <SessionSummary>[];
    state = AsyncData<List<SessionSummary>>(
      current.where((session) => session.id != id).toList(growable: false),
    );
    await _store.applySync(
      SessionSyncPage(
        cursor: await _store.readCursor(),
        sessions: const <SessionSummary>[],
        deletedSessionIds: <String>[id],
        hasMore: false,
        incremental: true,
      ),
    );
  }

  Future<void> _syncQuietly() async {
    try {
      final sessions = await _syncWithServer();
      state = AsyncData<List<SessionSummary>>(sessions);
    } on Object {
      // Keep the local list visible; pull-to-refresh surfaces hard failures.
    }
  }

  Future<List<SessionSummary>> _syncWithFallback() async {
    try {
      return await _syncWithServer();
    } on Object {
      final cached = await _store.readSummaries();
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<List<SessionSummary>> _syncWithServer() async {
    var cursor = await _store.readCursor();
    var pageCount = 0;
    while (true) {
      final page = await _loadSyncPage(cursor);
      await _store.applySync(page);
      pageCount += 1;
      if (!page.hasMore || page.cursor <= cursor || pageCount >= 20) break;
      cursor = page.cursor;
    }
    return _store.readSummaries();
  }

  Future<SessionSyncPage> _loadSyncPage(int cursor) async {
    try {
      return await _api.syncSessions(cursor: cursor, limit: 200);
    } on Object {
      if (cursor != 0) rethrow;
      final sessions = await _api.listSessions(limit: 200);
      return SessionSyncPage(
        cursor: sessions.fold<int>(
          0,
          (maxRevision, session) =>
              session.revision > maxRevision ? session.revision : maxRevision,
        ),
        sessions: sessions,
        deletedSessionIds: const <String>[],
        hasMore: false,
        incremental: false,
      );
    }
  }
}
