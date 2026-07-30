import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/quiz_attempt.dart';
import 'cache_namespace.dart';

/// Produces a stable, non-identifying storage namespace for one server user.
///
/// Only the normalized server origin and user id are hashed. The resulting
/// lowercase SHA-256 digest is safe to use in a file name and does not expose
/// either input in backups or directory listings.
String buildAttemptHistoryNamespace({
  required String serverUrl,
  required String userId,
}) {
  return buildScopedCacheNamespace(serverUrl: serverUrl, userId: userId);
}

class AttemptHistoryStore {
  AttemptHistoryStore({
    Future<Directory> Function()? directoryProvider,
    this.maxEntries = 200,
    String? namespace,
  })  : namespace = _validateNamespace(namespace),
        _directoryProvider =
            directoryProvider ?? getApplicationSupportDirectory;

  factory AttemptHistoryStore.scoped({
    required String serverUrl,
    required String userId,
    Future<Directory> Function()? directoryProvider,
    int maxEntries = 200,
  }) {
    return AttemptHistoryStore(
      directoryProvider: directoryProvider,
      maxEntries: maxEntries,
      namespace: buildAttemptHistoryNamespace(
        serverUrl: serverUrl,
        userId: userId,
      ),
    );
  }

  final Future<Directory> Function() _directoryProvider;
  final int maxEntries;
  final String? namespace;
  Future<void> _writeQueue = Future<void>.value();

  Future<List<QuizAttempt>> readAll() async {
    await _writeQueue;
    final file = await _historyFile();
    if (!await file.exists()) return const <QuizAttempt>[];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const <QuizAttempt>[];
      final attempts = <QuizAttempt>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          attempts.add(
            QuizAttempt.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
        } on FormatException {
          // Keep valid entries even if a prior app version wrote one bad item.
        }
      }
      attempts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return List<QuizAttempt>.unmodifiable(attempts);
    } on FormatException {
      return const <QuizAttempt>[];
    }
  }

  Future<void> save(QuizAttempt attempt) {
    return _enqueue(() async {
      final attempts = (await _readWithoutQueue()).toList(growable: true)
        ..removeWhere((item) => item.id == attempt.id)
        ..insert(0, attempt);
      if (attempts.length > maxEntries) {
        attempts.removeRange(maxEntries, attempts.length);
      }
      await _write(attempts);
    });
  }

  Future<void> clear() => _enqueue(() async {
        final file = await _historyFile();
        if (await file.exists()) await file.delete();
      });

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _writeQueue.then((_) => operation());
    _writeQueue = next.catchError((_) {});
    return next;
  }

  Future<List<QuizAttempt>> _readWithoutQueue() async {
    final file = await _historyFile();
    if (!await file.exists()) return const <QuizAttempt>[];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const <QuizAttempt>[];
      return decoded
          .whereType<Map>()
          .map(
            (item) => QuizAttempt.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const <QuizAttempt>[];
    }
  }

  Future<void> _write(List<QuizAttempt> attempts) async {
    final file = await _historyFile();
    final temporary = File('${file.path}.tmp');
    final payload = jsonEncode(attempts.map((item) => item.toJson()).toList());
    await temporary.writeAsString(payload, flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<File> _historyFile() async {
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    final suffix = namespace == null ? '' : '_$namespace';
    return File(
      '${directory.path}${Platform.pathSeparator}quiz_attempts$suffix.json',
    );
  }

  static String? _validateNamespace(String? value) =>
      validateCacheNamespace(value);
}
