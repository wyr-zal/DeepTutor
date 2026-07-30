import 'package:flutter/material.dart';

import '../../api/attempt_api.dart';
import '../../api/session_api.dart';
import '../../models/judge_result.dart';
import '../../models/quiz_attempt.dart';
import '../../models/session_summary.dart';
import '../../services/attempt_history_store.dart';
import '../../services/session_summary_cache_store.dart';

class AttemptHistoryPage extends StatefulWidget {
  const AttemptHistoryPage({
    super.key,
    required this.store,
    this.sessionRepository,
    this.sessionCacheStore,
    this.attemptRepository,
  });

  final AttemptHistoryStore store;
  final SessionRepository? sessionRepository;
  final SessionSummaryCacheStore? sessionCacheStore;
  final AttemptRepository? attemptRepository;

  @override
  State<AttemptHistoryPage> createState() => _AttemptHistoryPageState();
}

class _AttemptHistoryPageState extends State<AttemptHistoryPage> {
  late Future<List<QuizAttempt>> _attempts;
  late Future<List<SessionSummary>> _sessions;

  @override
  void initState() {
    super.initState();
    _attempts = _loadAttempts();
    _sessions = _loadSessions();
  }

  @override
  void didUpdateWidget(covariant AttemptHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _attempts = _loadAttempts();
    }
    if (oldWidget.attemptRepository != widget.attemptRepository) {
      _attempts = _loadAttempts();
    }
    if (oldWidget.sessionRepository != widget.sessionRepository ||
        oldWidget.sessionCacheStore != widget.sessionCacheStore) {
      _sessions = _loadSessions();
    }
  }

  Future<void> _refresh() async {
    final attempts = _loadAttempts();
    final sessions = _loadSessions();
    setState(() {
      _attempts = attempts;
      _sessions = sessions;
    });
    await Future.wait<void>(<Future<void>>[
      attempts.then<void>((_) {}, onError: (_) {}),
      sessions.then<void>((_) {}, onError: (_) {}),
    ]);
  }

  Future<void> _refreshAttempts() async {
    final attempts = _loadAttempts();
    setState(() => _attempts = attempts);
    await attempts.then<void>((_) {}, onError: (_) {});
  }

  Future<void> _refreshSessions() async {
    final sessions = _loadSessions();
    setState(() => _sessions = sessions);
    await sessions.then<void>((_) {}, onError: (_) {});
  }

  Future<List<SessionSummary>> _loadSessions() async {
    final repository = widget.sessionRepository;
    final cache = widget.sessionCacheStore;
    if (repository == null) {
      return (await cache?.read())?.items ?? const <SessionSummary>[];
    }
    try {
      final sessions = await repository.listSessions();
      await cache?.write(
        items: sessions,
        serverUrl: cache.serverUrlHint ?? '',
        userId: cache.userIdHint ?? '',
      );
      return sessions;
    } catch (_) {
      final cached = await cache?.read();
      if (cached != null) return cached.items;
      rethrow;
    }
  }

  Future<List<QuizAttempt>> _loadAttempts() async {
    final repository = widget.attemptRepository;
    if (repository == null) return widget.store.readAll();
    try {
      return await repository.listAttempts();
    } catch (_) {
      return widget.store.readAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('学习历史')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            const _SectionHeader(
              icon: Icons.forum_outlined,
              title: '服务端会话',
              description: '在其他设备上的学习对话也会显示在这里',
            ),
            FutureBuilder<List<SessionSummary>>(
              future: _sessions,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _HistoryLoading(label: '正在同步会话历史…');
                }
                if (snapshot.hasError) {
                  return _HistoryMessage(
                    icon: Icons.cloud_off_outlined,
                    title: '服务端会话加载失败',
                    description: '请检查网络或服务器状态后重试。',
                    actionLabel: '重试同步',
                    onAction: _refreshSessions,
                  );
                }
                final sessions = snapshot.data ?? const <SessionSummary>[];
                if (sessions.isEmpty) {
                  return const _HistoryMessage(
                    icon: Icons.forum_outlined,
                    title: '暂无服务端会话',
                    description: '完成一次学习对话后，会话会出现在这里。',
                  );
                }
                return Column(
                  children: <Widget>[
                    for (var index = 0; index < sessions.length; index++) ...[
                      if (index > 0) const SizedBox(height: 8),
                      _SessionCard(session: sessions[index]),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            const _SectionHeader(
              icon: Icons.quiz_outlined,
              title: '答题记录',
              description: '优先同步服务端；网络不可用时显示本机缓存',
            ),
            FutureBuilder<List<QuizAttempt>>(
              future: _attempts,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _HistoryLoading(label: '正在读取本机记录…');
                }
                if (snapshot.hasError) {
                  return _HistoryMessage(
                    icon: Icons.error_outline,
                    title: '本机答题记录读取失败',
                    description: '本机数据没有被修改，可重试读取。',
                    actionLabel: '重试读取',
                    onAction: _refreshAttempts,
                  );
                }
                final attempts = snapshot.data ?? const <QuizAttempt>[];
                if (attempts.isEmpty) {
                  return const _HistoryMessage(
                    icon: Icons.history,
                    title: '暂无答题记录',
                    description: '完成一道题的语音作答后，结果会保存在这里。',
                  );
                }
                return Column(
                  children: <Widget>[
                    for (var index = 0; index < attempts.length; index++) ...[
                      if (index > 0) const SizedBox(height: 8),
                      _AttemptCard(attempt: attempts[index]),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 24, semanticLabel: title),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});

  final SessionSummary session;

  @override
  Widget build(BuildContext context) {
    final title = session.title.isEmpty ? '未命名会话' : session.title;
    final details = <String>[
      '${session.messageCount} 条消息',
      if (session.capability.isNotEmpty) session.capability,
      if (session.activityAt != null) _formatTime(session.activityAt!),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              details.join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (session.lastMessage.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                session.lastMessage,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoryLoading extends StatelessWidget {
  const _HistoryLoading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _AttemptCard extends StatelessWidget {
  const _AttemptCard({required this.attempt});

  final QuizAttempt attempt;

  @override
  Widget build(BuildContext context) {
    final status = switch (attempt.result.verdict) {
      JudgeVerdict.correct => '推断：正确',
      JudgeVerdict.partiallyCorrect => '推断：部分正确',
      JudgeVerdict.incorrect => '推断：不正确',
      JudgeVerdict.unknown => '判定状态未识别',
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(
          attempt.question.question,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text('$status · ${_formatTime(attempt.createdAt)}'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Divider(),
          Text('你的答案', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(attempt.userAnswer),
          const SizedBox(height: 12),
          Text('AI 返回文字', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(attempt.result.text),
        ],
      ),
    );
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
    required this.icon,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 44, semanticLabel: title),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (description != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(description!, textAlign: TextAlign.center),
            ],
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
