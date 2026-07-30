import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../api/network_diagnostics.dart';
import '../../config/app_config.dart';
import '../../models/knowledge_base.dart';
import '../auth/server_connection_controller.dart';
import '../auth/transport_diagnostics_controller.dart';
import 'knowledge_list_controller.dart';

class HomePage extends ConsumerWidget {
  const HomePage({
    super.key,
    required this.onSelectKnowledgeBase,
    this.onHistory,
    this.onLogout,
  });

  final ValueChanged<KnowledgeBase> onSelectKnowledgeBase;
  final VoidCallback? onHistory;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final knowledgeBases = ref.watch(knowledgeListControllerProvider);
    final connection = ref.watch(serverConnectionControllerProvider);
    final transport = ref.watch(transportDiagnosticsProvider);
    final config = ref.watch(appConnectionConfigProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('DeepTutor'),
        actions: <Widget>[
          if (onHistory != null)
            IconButton(
              onPressed: onHistory,
              tooltip: '答题历史',
              icon: const Icon(Icons.history),
            ),
          IconButton(
            onPressed: () =>
                ref.read(knowledgeListControllerProvider.notifier).refresh(),
            tooltip: '刷新知识库',
            icon: const Icon(Icons.refresh),
          ),
          if (onLogout != null)
            IconButton(
              onPressed: onLogout,
              tooltip: '退出登录',
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await Future.wait<void>(<Future<void>>[
              ref.read(serverConnectionControllerProvider.notifier).retry(),
              ref.read(knowledgeListControllerProvider.notifier).refresh(),
            ]);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              _ConnectionBanner(
                snapshot: connection.valueOrNull,
                loading: connection.isLoading,
                onRetry: () {
                  ref.read(serverConnectionControllerProvider.notifier).retry();
                  ref.read(knowledgeListControllerProvider.notifier).refresh();
                },
              ),
              if (config.diagnosticsEnabled) ...<Widget>[
                const SizedBox(height: 12),
                _DiagnosticsCard(
                  config: config,
                  connection: connection,
                  knowledge: knowledgeBases,
                  transport: transport,
                ),
              ],
              const SizedBox(height: 18),
              Text('题库', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '已同步的题库会保存在本机；出题和判题仍需要联网。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              knowledgeBases.when(
                loading: () {
                  final previous = knowledgeBases.valueOrNull;
                  if (previous != null && previous.items.isNotEmpty) {
                    return _KnowledgeList(
                      state: previous,
                      onSelectKnowledgeBase: onSelectKnowledgeBase,
                    );
                  }
                  return const _LoadingState();
                },
                error: (error, _) => _ErrorState(
                  message: _readableError(error),
                  onRetry: () => ref
                      .read(knowledgeListControllerProvider.notifier)
                      .refresh(),
                ),
                data: (state) => state.items.isEmpty
                    ? _EmptyState(
                        message: state.message,
                        onRefresh: () => ref
                            .read(knowledgeListControllerProvider.notifier)
                            .refresh(),
                      )
                    : _KnowledgeList(
                        state: state,
                        onSelectKnowledgeBase: onSelectKnowledgeBase,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _readableError(Object error) {
    if (error is KnowledgeListException) return error.message;
    return '知识库加载失败，请检查网络后重试。';
  }
}

class _KnowledgeList extends StatelessWidget {
  const _KnowledgeList({
    required this.state,
    required this.onSelectKnowledgeBase,
  });

  final KnowledgeListState state;
  final ValueChanged<KnowledgeBase> onSelectKnowledgeBase;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (state.fromCache)
        _InlineNotice(
          icon: Icons.offline_bolt_outlined,
          message: state.lastSyncedAt == null
              ? '当前显示本机缓存。'
              : '当前显示本机缓存，上次同步 ${_formatTime(state.lastSyncedAt!)}。',
        ),
      if (state.message != null && state.fromCache)
        _InlineNotice(
          icon: Icons.info_outline,
          message: state.message!,
        ),
      for (final knowledgeBase in state.items)
        _KnowledgeBaseTile(
          knowledgeBase: knowledgeBase,
          onTap: knowledgeBase.available
              ? () => onSelectKnowledgeBase(knowledgeBase)
              : null,
          cached: state.fromCache,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < children.length; index++) ...<Widget>[
          if (index > 0) const SizedBox(height: 10),
          children[index],
        ],
      ],
    );
  }
}

class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard({
    required this.config,
    required this.connection,
    required this.knowledge,
    required this.transport,
  });

  final AppConnectionConfig config;
  final AsyncValue<ServerConnectionSnapshot> connection;
  final AsyncValue<KnowledgeListState> knowledge;
  final AsyncValue<TransportDiagnosticsReport?> transport;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = _diagnosticText();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.bug_report_outlined,
                    color: colors.onTertiaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '诊断模式',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colors.onTertiaryContainer,
                        ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('诊断信息已复制')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('复制'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onTertiaryContainer,
                    fontFamily: 'monospace',
                  ),
            ),
          ],
        ),
      ),
    );
  }

  String _diagnosticText() {
    final lines = <String>[
      'DeepTutor mobile diagnostics',
      'fixedUrl=${config.fixedServerUrl.trim().isEmpty ? '<empty>' : config.fixedServerUrl.trim()}',
      'personalServerMode=${config.personalServerMode}',
    ];

    final connectionValue = connection.valueOrNull;
    if (connectionValue != null) {
      lines.addAll(<String>[
        '',
        '[auth/status]',
        'uiStatus=${connectionValue.status.name}',
        'uiMessage=${connectionValue.message}',
        if (connectionValue.checkedAt != null)
          'checkedAt=${connectionValue.checkedAt!.toIso8601String()}',
        if (connectionValue.diagnosticDetails != null)
          connectionValue.diagnosticDetails!,
      ]);
    } else if (connection.hasError) {
      lines.addAll(<String>[
        '',
        '[auth/status]',
        NetworkDiagnostics.describeObject(connection.error!),
      ]);
    } else {
      lines.addAll(<String>[
        '',
        '[auth/status]',
        'checking=true',
      ]);
    }

    final knowledgeValue = knowledge.valueOrNull;
    if (knowledgeValue != null) {
      lines.addAll(<String>[
        '',
        '[knowledge/list]',
        'source=${knowledgeValue.source.name}',
        'items=${knowledgeValue.items.length}',
        if (knowledgeValue.message != null)
          'uiMessage=${knowledgeValue.message}',
        if (knowledgeValue.lastSyncedAt != null)
          'lastSyncedAt=${knowledgeValue.lastSyncedAt!.toIso8601String()}',
        if (knowledgeValue.diagnosticDetails != null)
          knowledgeValue.diagnosticDetails!,
      ]);
    } else if (knowledge.hasError) {
      lines.addAll(<String>[
        '',
        '[knowledge/list]',
        NetworkDiagnostics.describeObject(knowledge.error!),
      ]);
    } else {
      lines.addAll(<String>[
        '',
        '[knowledge/list]',
        'checking=true',
      ]);
    }

    final transportValue = transport.valueOrNull;
    if (transportValue != null) {
      lines.addAll(<String>[
        '',
        '[transport]',
        transportValue.toDisplayText(),
      ]);
    } else if (transport.hasError) {
      lines.addAll(<String>[
        '',
        '[transport]',
        NetworkDiagnostics.describeObject(transport.error!),
      ]);
    } else {
      lines.addAll(<String>[
        '',
        '[transport]',
        'checking=true',
      ]);
    }

    return lines.join('\n');
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({
    required this.snapshot,
    required this.loading,
    required this.onRetry,
  });

  final ServerConnectionSnapshot? snapshot;
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final current = snapshot ?? const ServerConnectionSnapshot.checking();
    final (icon, title, background, foreground) = switch (current.status) {
      ServerConnectionStatus.online => (
          Icons.cloud_done_outlined,
          '服务器已连接',
          colors.primaryContainer,
          colors.onPrimaryContainer,
        ),
      ServerConnectionStatus.authMisconfigured => (
          Icons.admin_panel_settings_outlined,
          '服务器配置不匹配',
          colors.errorContainer,
          colors.onErrorContainer,
        ),
      ServerConnectionStatus.offline => (
          Icons.cloud_off_outlined,
          '离线浏览缓存',
          colors.surfaceContainerLow,
          colors.onSurface,
        ),
      ServerConnectionStatus.checking => (
          Icons.sync,
          '正在检查连接',
          colors.surfaceContainerLow,
          colors.onSurface,
        ),
    };
    return Semantics(
      liveRegion: true,
      label: '$title。${current.message}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (loading)
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(icon, color: foreground),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: foreground),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      current.checkedAt == null
                          ? current.message
                          : '${current.message} · ${_formatTime(current.checkedAt!)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: foreground),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: loading ? null : onRetry,
                child: const Text('重试同步'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KnowledgeBaseTile extends StatelessWidget {
  const _KnowledgeBaseTile({
    required this.knowledgeBase,
    required this.onTap,
    this.cached = false,
  });

  final KnowledgeBase knowledgeBase;
  final VoidCallback? onTap;
  final bool cached;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = <String>[
      if (knowledgeBase.documentCount != null)
        '${knowledgeBase.documentCount} 个文档',
      if (knowledgeBase.provenanceLabel != null) knowledgeBase.provenanceLabel!,
      if (!knowledgeBase.available) '暂不可用',
      if (cached) '本机缓存',
    ].join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        enabled: onTap != null,
        onTap: onTap,
        minVerticalPadding: 18,
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          child: const Icon(Icons.library_books_outlined),
        ),
        title: Row(
          children: <Widget>[
            Flexible(
              child: Text(
                knowledgeBase.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (knowledgeBase.isDefault) ...<Widget>[
              const SizedBox(width: 8),
              const _Tag(label: '默认'),
            ],
            if (knowledgeBase.readOnly) ...<Widget>[
              const SizedBox(width: 6),
              const _Tag(label: '只读'),
            ],
          ],
        ),
        subtitle: detail.isEmpty
            ? const Text('点击配置练习')
            : Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: colors.onSecondaryContainer),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) => Center(
        child: Semantics(
          liveRegion: true,
          label: '正在加载知识库',
          child: const CircularProgressIndicator(),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh, this.message});

  final VoidCallback onRefresh;
  final String? message;

  @override
  Widget build(BuildContext context) => _CenteredMessage(
        icon: Icons.library_books_outlined,
        title: '暂无已同步题库',
        message: message == null
            ? '首次使用需要联网同步服务器题库；同步成功后会缓存在本机。'
            : '$message\n\n首次使用需要联网同步服务器题库；同步成功后会缓存在本机。',
        actionLabel: '重试同步',
        onAction: onRefresh,
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _CenteredMessage(
        icon: Icons.cloud_off_outlined,
        title: '加载失败',
        message: message,
        actionLabel: '重试',
        onAction: onRetry,
      );
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: colors.outline),
            const SizedBox(width: 10),
            Expanded(
              child:
                  Text(message, style: Theme.of(context).textTheme.bodySmall),
            ),
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

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon,
                  size: 52, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      );
}
