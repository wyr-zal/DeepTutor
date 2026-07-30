import 'dart:io';

import 'package:deeptutor_mobile/models/knowledge_base.dart';
import 'package:deeptutor_mobile/models/session_summary.dart';
import 'package:deeptutor_mobile/services/cache_namespace.dart';
import 'package:deeptutor_mobile/services/knowledge_cache_store.dart';
import 'package:deeptutor_mobile/services/session_summary_cache_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cache namespace is scoped by server and user', () {
    final first = buildScopedCacheNamespace(
      serverUrl: 'https://deeptutor.cliproxy.com.cn/',
      userId: 'local-admin',
    );
    final second = buildScopedCacheNamespace(
      serverUrl: 'https://deeptutor.cliproxy.com.cn',
      userId: 'another-user',
    );

    expect(first, isNot(second));
    expect(validateCacheNamespace(first), first);
    expect(
      () => validateCacheNamespace('../bad'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('knowledge cache writes and reads the server-scoped list', () async {
    final directory = await Directory.systemTemp.createTemp(
      'deeptutor_knowledge_cache_test_',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final syncedAt = DateTime.utc(2026, 7, 30, 8);
    final store = KnowledgeCacheStore.scoped(
      serverUrl: 'https://deeptutor.cliproxy.com.cn',
      userId: 'local-admin',
      directoryProvider: () async => directory,
    );

    await store.write(
      items: const <KnowledgeBase>[
        KnowledgeBase(
          id: 'kb-1',
          name: 'math',
          isDefault: true,
          statistics: <String, Object?>{'document_count': 3},
        ),
      ],
      serverUrl: 'https://deeptutor.cliproxy.com.cn',
      userId: 'local-admin',
      lastSyncedAt: syncedAt,
    );

    final cached = await store.read();

    expect(cached, isNotNull);
    expect(cached!.items.single.name, 'math');
    expect(cached.items.single.documentCount, 3);
    expect(cached.lastSyncedAt, syncedAt);
    expect(cached.serverUrl, 'https://deeptutor.cliproxy.com.cn');
    expect(cached.userId, 'local-admin');
  });

  test('session summary cache writes and reads sessions', () async {
    final directory = await Directory.systemTemp.createTemp(
      'deeptutor_session_cache_test_',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final createdAt = DateTime.utc(2026, 7, 29, 9);
    final updatedAt = DateTime.utc(2026, 7, 30, 9);
    final store = SessionSummaryCacheStore.scoped(
      serverUrl: 'https://deeptutor.cliproxy.com.cn',
      userId: 'local-admin',
      directoryProvider: () async => directory,
    );

    await store.write(
      items: <SessionSummary>[
        SessionSummary(
          id: 'session-1',
          title: '函数复习',
          capability: 'chat',
          status: 'idle',
          messageCount: 5,
          lastMessage: '继续讲顶点式',
          createdAt: createdAt,
          updatedAt: updatedAt,
        ),
      ],
      serverUrl: 'https://deeptutor.cliproxy.com.cn',
      userId: 'local-admin',
    );

    final cached = await store.read();

    expect(cached, isNotNull);
    expect(cached!.items.single.id, 'session-1');
    expect(cached.items.single.title, '函数复习');
    expect(cached.items.single.activityAt, updatedAt);
    expect(cached.serverUrl, 'https://deeptutor.cliproxy.com.cn');
    expect(cached.userId, 'local-admin');
  });
}
