import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/session_summary.dart';
import 'cache_namespace.dart';

class CachedSessionSummaries {
  const CachedSessionSummaries({
    required this.items,
    required this.lastSyncedAt,
    required this.serverUrl,
    required this.userId,
  });

  const CachedSessionSummaries.empty()
      : items = const <SessionSummary>[],
        lastSyncedAt = null,
        serverUrl = null,
        userId = null;

  final List<SessionSummary> items;
  final DateTime? lastSyncedAt;
  final String? serverUrl;
  final String? userId;
}

class SessionSummaryCacheStore {
  SessionSummaryCacheStore({
    Future<Directory> Function()? directoryProvider,
    String? namespace,
    this.serverUrlHint,
    this.userIdHint,
  })  : namespace = validateCacheNamespace(namespace),
        _directoryProvider =
            directoryProvider ?? getApplicationSupportDirectory;

  factory SessionSummaryCacheStore.scoped({
    required String serverUrl,
    required String userId,
    Future<Directory> Function()? directoryProvider,
  }) {
    return SessionSummaryCacheStore(
      directoryProvider: directoryProvider,
      namespace:
          buildScopedCacheNamespace(serverUrl: serverUrl, userId: userId),
      serverUrlHint: serverUrl,
      userIdHint: userId,
    );
  }

  final Future<Directory> Function() _directoryProvider;
  final String? namespace;
  final String? serverUrlHint;
  final String? userIdHint;

  Future<CachedSessionSummaries?> read() async {
    final file = await _cacheFile();
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final items = decoded['items'];
      if (items is! Iterable) return null;
      final parsed = <SessionSummary>[];
      for (final item in items) {
        if (item is! Map) continue;
        try {
          parsed.add(
            SessionSummary.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
        } on FormatException {
          // Keep valid cache rows from older app versions.
        }
      }
      return CachedSessionSummaries(
        items: List<SessionSummary>.unmodifiable(parsed),
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
    required List<SessionSummary> items,
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
      '${directory.path}${Platform.pathSeparator}session_summaries$suffix.json',
    );
  }
}
