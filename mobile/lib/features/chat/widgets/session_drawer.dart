import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/session_summary.dart';
import '../chat_controller.dart';
import '../session_list_controller.dart';

class SessionDrawer extends ConsumerWidget {
  const SessionDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionListControllerProvider);
    final activeSessionId = ref.watch(
      chatControllerProvider.select((state) => state.sessionId),
    );
    return Drawer(
      child: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '聊天记录',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新会话',
                    onPressed: () => ref
                        .read(sessionListControllerProvider.notifier)
                        .refresh(),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    await ref
                        .read(chatControllerProvider.notifier)
                        .newSession();
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('新会话'),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: sessions.when(
                data: (items) => items.isEmpty
                    ? const _EmptySessions()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: items.length,
                        itemBuilder: (context, index) => _SessionTile(
                          session: items[index],
                          selected: items[index].id == activeSessionId,
                        ),
                      ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => _SessionLoadError(
                  onRetry: () => ref
                      .read(sessionListControllerProvider.notifier)
                      .refresh(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.session, required this.selected});

  final SessionSummary session;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      selected: selected,
      leading: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          const Icon(Icons.chat_bubble_outline),
          if (session.status == 'running')
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        session.title.isEmpty ? '未命名会话' : session.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        session.lastMessage.isEmpty
            ? '${session.messageCount} 条消息'
            : session.lastMessage,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        tooltip: '会话操作',
        onSelected: (action) async {
          if (action == 'rename') {
            await _rename(context, ref);
          } else if (action == 'delete') {
            await _delete(context, ref);
          }
        },
        itemBuilder: (_) => const <PopupMenuEntry<String>>[
          PopupMenuItem(value: 'rename', child: Text('重命名')),
          PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
      onTap: () async {
        Navigator.pop(context);
        await ref.read(chatControllerProvider.notifier).loadSession(session.id);
      },
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: session.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(labelText: '会话标题'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty || !context.mounted) return;
    try {
      await ref.read(sessionListControllerProvider.notifier).rename(
            session.id,
            title,
          );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('重命名失败，请检查网络后重试。')),
        );
      }
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除会话？'),
        content: const Text('删除后无法从聊天记录中恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(sessionListControllerProvider.notifier).remove(session.id);
      if (selected) {
        await ref.read(chatControllerProvider.notifier).newSession();
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除失败，请检查网络后重试。')),
        );
      }
    }
  }
}

class _EmptySessions extends StatelessWidget {
  const _EmptySessions();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '还没有聊天记录。\n发送第一条消息后会出现在这里。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
}

class _SessionLoadError extends StatelessWidget {
  const _SessionLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.cloud_off_outlined),
              const SizedBox(height: 8),
              const Text('无法加载聊天记录'),
              TextButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      );
}
