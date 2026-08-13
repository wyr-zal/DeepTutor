import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/network_diagnostics.dart';
import '../../config/app_config.dart';
import '../auth/server_connection_controller.dart';
import '../auth/transport_diagnostics_controller.dart';
import '../home/knowledge_list_controller.dart';

/// Standalone network diagnostics page.
///
/// Reachable from the chat shell overflow menu. Aggregates the auth/status,
/// knowledge/list and transport probes into a single copyable report.
class DiagnosticsPage extends ConsumerWidget {
  const DiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(serverConnectionControllerProvider);
    final knowledge = ref.watch(knowledgeListControllerProvider);
    final transport = ref.watch(transportDiagnosticsProvider);
    final config = ref.watch(appConnectionConfigProvider);
    final text = _diagnosticText(
      config: config,
      connection: connection,
      knowledge: knowledge,
      transport: transport,
    );
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('网络诊断'),
        actions: <Widget>[
          IconButton(
            tooltip: '重新检测',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(serverConnectionControllerProvider.notifier).retry();
              ref.read(knowledgeListControllerProvider.notifier).refresh();
              ref.invalidate(transportDiagnosticsProvider);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.bug_report_outlined, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '诊断信息',
                    style: Theme.of(context).textTheme.titleMedium,
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
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                border: Border.all(color: colors.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: SelectableText(
                  text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _diagnosticText({
    required AppConnectionConfig config,
    required AsyncValue<ServerConnectionSnapshot> connection,
    required AsyncValue<KnowledgeListState> knowledge,
    required AsyncValue<TransportDiagnosticsReport?> transport,
  }) {
    final lines = <String>[
      'DeepTutor mobile diagnostics',
      'fixedUrl=${config.fixedServerUrl.trim().isEmpty ? '<empty>' : config.fixedServerUrl.trim()}',
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
      lines.addAll(<String>['', '[auth/status]', 'checking=true']);
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
      lines.addAll(<String>['', '[knowledge/list]', 'checking=true']);
    }

    final transportValue = transport.valueOrNull;
    if (transportValue != null) {
      lines.addAll(<String>['', '[transport]', transportValue.toDisplayText()]);
    } else if (transport.hasError) {
      lines.addAll(<String>[
        '',
        '[transport]',
        NetworkDiagnostics.describeObject(transport.error!),
      ]);
    } else {
      lines.addAll(<String>['', '[transport]', 'checking=true']);
    }

    return lines.join('\n');
  }
}
