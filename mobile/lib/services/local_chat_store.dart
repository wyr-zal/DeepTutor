import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import '../api/session_api.dart';
import '../models/chat_message.dart';
import '../models/session_summary.dart';
import 'cache_namespace.dart';

class LocalConversation {
  const LocalConversation({
    required this.sessionId,
    required this.title,
    required this.messages,
    required this.detailRevision,
  });

  final String sessionId;
  final String title;
  final List<ChatMessage> messages;
  final int detailRevision;
}

class LocalChatStore {
  LocalChatStore({
    required String namespace,
    sqflite.DatabaseFactory? databaseFactory,
    Future<String> Function()? databasePathProvider,
  })  : namespace = validateCacheNamespace(namespace)!,
        _databaseFactory = databaseFactory,
        _databasePathProvider = databasePathProvider;

  factory LocalChatStore.scoped({
    required String serverUrl,
    required String userId,
  }) {
    return LocalChatStore(
      namespace: buildScopedCacheNamespace(
        serverUrl: serverUrl,
        userId: userId,
      ),
    );
  }

  final String namespace;
  final sqflite.DatabaseFactory? _databaseFactory;
  final Future<String> Function()? _databasePathProvider;
  sqflite.Database? _database;

  Future<int> readCursor() async {
    final db = await _open();
    final rows = await db.query(
      'sync_state',
      columns: const <String>['value'],
      where: 'key = ?',
      whereArgs: const <Object>['session_cursor'],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.single['value']?.toString() ?? '') ?? 0;
  }

  Future<List<SessionSummary>> readSummaries() async {
    final db = await _open();
    final rows = await db.query(
      'sessions',
      orderBy: 'activity_at DESC, id ASC',
    );
    return List<SessionSummary>.unmodifiable(
      rows.map(_summaryFromRow),
    );
  }

  Future<SessionSummary?> readSummary(String sessionId) async {
    final db = await _open();
    final rows = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: <Object>[sessionId],
      limit: 1,
    );
    return rows.isEmpty ? null : _summaryFromRow(rows.single);
  }

  Future<void> applySync(SessionSyncPage page) async {
    final db = await _open();
    await db.transaction((txn) async {
      for (final id in page.deletedSessionIds) {
        await txn.delete(
          'sessions',
          where: 'id = ?',
          whereArgs: <Object>[id],
        );
      }
      for (final summary in page.sessions) {
        await txn.rawInsert(
          '''
          INSERT INTO sessions (
            id, title, capability, status, message_count, last_message,
            created_at, updated_at, activity_at, revision
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            capability = excluded.capability,
            status = excluded.status,
            message_count = excluded.message_count,
            last_message = excluded.last_message,
            created_at = excluded.created_at,
            updated_at = excluded.updated_at,
            activity_at = excluded.activity_at,
            revision = excluded.revision
          ''',
          <Object?>[
            summary.id,
            summary.title,
            summary.capability,
            summary.status,
            summary.messageCount,
            summary.lastMessage,
            _millis(summary.createdAt),
            _millis(summary.updatedAt),
            _millis(summary.activityAt) ?? 0,
            summary.revision,
          ],
        );
      }
      await txn.insert(
        'sync_state',
        <String, Object?>{
          'key': 'session_cursor',
          'value': page.cursor.toString(),
        },
        conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
      );
    });
  }

  Future<LocalConversation?> readConversation(String sessionId) async {
    final db = await _open();
    final sessionRows = await db.query(
      'sessions',
      columns: const <String>['title', 'detail_revision'],
      where: 'id = ?',
      whereArgs: <Object>[sessionId],
      limit: 1,
    );
    if (sessionRows.isEmpty) return null;
    final messageRows = await db.query(
      'chat_messages',
      columns: const <String>['payload_json'],
      where: 'session_id = ?',
      whereArgs: <Object>[sessionId],
      orderBy: 'position ASC',
    );
    if (messageRows.isEmpty) return null;
    final messages = <ChatMessage>[];
    for (final row in messageRows) {
      try {
        final payload = jsonDecode(row['payload_json']?.toString() ?? '');
        if (payload is Map) {
          messages.add(
            ChatMessage.fromJson(
              payload.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
        }
      } on FormatException {
        // Keep the rest of a valid conversation if one old row is malformed.
      }
    }
    if (messages.isEmpty) return null;
    return LocalConversation(
      sessionId: sessionId,
      title: sessionRows.single['title']?.toString() ?? '',
      messages: List<ChatMessage>.unmodifiable(messages),
      detailRevision:
          (sessionRows.single['detail_revision'] as num?)?.toInt() ?? -1,
    );
  }

  Future<void> writeConversation({
    required String sessionId,
    required String title,
    required List<ChatMessage> messages,
    required int detailRevision,
  }) async {
    final normalizedId = sessionId.trim();
    if (normalizedId.isEmpty) return;
    final db = await _open();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final lastText = messages.reversed
        .map((item) => item.textBuffer.trim())
        .firstWhere((item) => item.isNotEmpty, orElse: () => '');
    final capability = messages.isNotEmpty
        ? messages.last.capability == ChatCapability.deepQuestion
            ? 'deep_question'
            : 'chat'
        : '';
    await db.transaction((txn) async {
      await txn.rawInsert(
        '''
        INSERT INTO sessions (
          id, title, capability, status, message_count, last_message,
          created_at, updated_at, activity_at, revision, detail_revision
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title,
          capability = excluded.capability,
          status = excluded.status,
          message_count = excluded.message_count,
          last_message = excluded.last_message,
          updated_at = excluded.updated_at,
          activity_at = excluded.activity_at,
          revision = MAX(revision, excluded.revision),
          detail_revision = excluded.detail_revision
        ''',
        <Object?>[
          normalizedId,
          title.trim(),
          capability,
          messages.any((item) => item.streaming) ? 'running' : 'idle',
          messages.length,
          lastText,
          now,
          now,
          now,
          detailRevision < 0 ? 0 : detailRevision,
          detailRevision,
        ],
      );
      await txn.delete(
        'chat_messages',
        where: 'session_id = ?',
        whereArgs: <Object>[normalizedId],
      );
      final batch = txn.batch();
      for (var index = 0; index < messages.length; index++) {
        batch.insert('chat_messages', <String, Object?>{
          'session_id': normalizedId,
          'position': index,
          'payload_json': jsonEncode(messages[index].toJson()),
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> updateDetailRevision(String sessionId, int revision) async {
    final db = await _open();
    await db.update(
      'sessions',
      <String, Object?>{'detail_revision': revision},
      where: 'id = ?',
      whereArgs: <Object>[sessionId],
    );
  }

  Future<void> deleteConversation(String sessionId) async {
    final db = await _open();
    await db.delete(
      'sessions',
      where: 'id = ?',
      whereArgs: <Object>[sessionId],
    );
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    await db?.close();
  }

  Future<sqflite.Database> _open() async {
    final existing = _database;
    if (existing != null) return existing;
    final factory = _databaseFactory ?? sqflite.databaseFactory;
    final databasePathProvider = _databasePathProvider;
    final path = databasePathProvider != null
        ? await databasePathProvider()
        : '${(await getApplicationSupportDirectory()).path}'
            '${Platform.pathSeparator}chat_$namespace.db';
    final database = await factory.openDatabase(
      path,
      options: sqflite.OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          final batch = db.batch();
          for (final statement in _schema) {
            batch.execute(statement);
          }
          await batch.commit(noResult: true);
        },
      ),
    );
    _database = database;
    return database;
  }

  static SessionSummary _summaryFromRow(Map<String, Object?> row) =>
      SessionSummary(
        id: row['id']?.toString() ?? '',
        title: row['title']?.toString() ?? '',
        capability: row['capability']?.toString() ?? '',
        status: row['status']?.toString() ?? '',
        messageCount: (row['message_count'] as num?)?.toInt() ?? 0,
        lastMessage: row['last_message']?.toString() ?? '',
        createdAt: _date(row['created_at']),
        updatedAt: _date(row['updated_at']),
        revision: (row['revision'] as num?)?.toInt() ?? 0,
      );

  static int? _millis(DateTime? value) => value?.toUtc().millisecondsSinceEpoch;

  static DateTime? _date(Object? value) {
    final millis = (value as num?)?.toInt();
    if (millis == null || millis <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  static const _schema = <String>[
    '''CREATE TABLE sessions (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL DEFAULT '',
      capability TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT '',
      message_count INTEGER NOT NULL DEFAULT 0,
      last_message TEXT NOT NULL DEFAULT '',
      created_at INTEGER,
      updated_at INTEGER,
      activity_at INTEGER NOT NULL DEFAULT 0,
      revision INTEGER NOT NULL DEFAULT 0,
      detail_revision INTEGER NOT NULL DEFAULT -1
    )''',
    'CREATE INDEX idx_local_sessions_activity ON sessions(activity_at DESC)',
    '''CREATE TABLE chat_messages (
      session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
      position INTEGER NOT NULL,
      payload_json TEXT NOT NULL,
      PRIMARY KEY (session_id, position)
    )''',
    '''CREATE TABLE sync_state (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )''',
  ];
}
