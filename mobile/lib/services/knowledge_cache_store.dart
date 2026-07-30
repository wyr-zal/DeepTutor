import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/knowledge_base.dart';
import 'cache_namespace.dart';

class CachedKnowledgeBases {
  const CachedKnowledgeBases({
    required this.items,
    required this.lastSyncedAt,
    required this.serverUrl,
    required this.userId,
  });

  const CachedKnowledgeBases.empty()
      : items = const <KnowledgeBase>[],
        lastSyncedAt = null,
        serverUrl = null,
        userId = null;

  final List<KnowledgeBase> items;
  final DateTime? lastSyncedAt;
  final String? serverUrl;
  final String? userId;
}

class KnowledgeCacheStore {
  KnowledgeCacheStore({
    Future<Directory> Function()? directoryProvider,
    String? namespace,
  })  : namespace = validateCacheNamespace(namespace),
        _directoryProvider =
            directoryProvider ?? getApplicationSupportDirectory;

  factory KnowledgeCacheStore.scoped({
    required String serverUrl,
    required String userId,
    Future<Directory> Function()? directoryProvider,
  }) {
    return KnowledgeCacheStore(
      directoryProvider: directoryProvider,
      namespace:
          buildScopedCacheNamespace(serverUrl: serverUrl, userId: userId),
    );
  }

  final Future<Directory> Function() _directoryProvider;
  final String? namespace;

  Future<CachedKnowledgeBases?> read() async {
    final file = await _cacheFile();
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final items = decoded['items'];
      if (items is! Iterable) return null;
      final parsed = <KnowledgeBase>[];
      for (final item in items) {
        if (item is! Map) continue;
        try {
          parsed.add(
            KnowledgeBase.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
        } on FormatException {
          // Keep valid cache rows from older app versions.
        }
      }
      return CachedKnowledgeBases(
        items: List<KnowledgeBase>.unmodifiable(parsed),
        lastSyncedAt: DateTime.tryParse(
          decoded['last_synced_at']?.toString() ?? '',
        )?.toUtc(),
        serverUrl: decoded['server_url']?.toString(),
        userId: decoded['user_id']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write({
    required List<KnowledgeBase> items,
    required String serverUrl,
    required String userId,
    DateTime? lastSyncedAt,
  }) async {
    final file = await _cacheFile();
    final temporary = File('${file.path}.tmp');
    final payload = <String, dynamic>{
      'version': 1,
      'server_url': serverUrl,
      'user_id': userId,
      'last_synced_at':
          (lastSyncedAt ?? DateTime.now().toUtc()).toUtc().toIso8601String(),
      'items': items.map((item) => item.toJson()).toList(),
    };
    await temporary.writeAsString(jsonEncode(payload), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<File> _cacheFile() async {
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    final suffix = namespace == null ? '' : '_$namespace';
    return File(
      '${directory.path}${Platform.pathSeparator}knowledge_bases$suffix.json',
    );
  }
}
