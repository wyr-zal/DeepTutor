import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../diagnostics/diagnostics_page.dart';
import '../settings/theme_picker_sheet.dart';
import 'chat_controller.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_message_list.dart';
import 'widgets/session_drawer.dart';

class ChatShellPage extends ConsumerWidget {
  const ChatShellPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatControllerProvider);
    final authEnabled =
        ref.watch(authControllerProvider).valueOrNull?.authEnabled == true;
    return Scaffold(
      endDrawer: const SessionDrawer(),
      endDrawerEnableOpenDragGesture: true,
      appBar: AppBar(
        title: Text(
          chat.sessionTitle?.trim().isNotEmpty == true
              ? chat.sessionTitle!
              : 'DeepTutor',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          Builder(
            builder: (context) => IconButton(
              tooltip: '聊天记录',
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              icon: const Icon(Icons.history),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (action) async {
              if (action == 'appearance') {
                await showThemePicker(context);
              } else if (action == 'diagnostics') {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const DiagnosticsPage(),
                  ),
                );
              } else if (action == 'logout') {
                await ref.read(authControllerProvider.notifier).logout();
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              const PopupMenuItem(
                value: 'appearance',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.palette_outlined),
                  title: Text('外观'),
                ),
              ),
              const PopupMenuItem(
                value: 'diagnostics',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.network_check),
                  title: Text('网络诊断'),
                ),
              ),
              if (authEnabled)
                const PopupMenuItem(
                  value: 'logout',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.logout),
                    title: Text('退出登录'),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (chat.error != null)
            MaterialBanner(
              content: Text(chat.error!),
              leading: const Icon(Icons.wifi_off_outlined),
              actions: <Widget>[
                TextButton(
                  onPressed: () =>
                      ref.read(chatControllerProvider.notifier).reconnect(),
                  child: const Text('重连'),
                ),
              ],
            ),
          Expanded(
            child: chat.isLoadingSession
                ? const Center(child: CircularProgressIndicator())
                : ChatMessageList(
                    messages: chat.messages,
                    onUnauthorized: () {
                      ref.read(authControllerProvider.notifier).logout();
                    },
                    onAnswerStateChanged: (messageId, questionKey, value) {
                      ref
                          .read(chatControllerProvider.notifier)
                          .updateAnswerState(messageId, questionKey, value);
                    },
                    onSubmitUserReply: (messageId, text, answers) {
                      ref.read(chatControllerProvider.notifier).submitUserReply(
                            messageId,
                            text: text,
                            answers: answers,
                          );
                    },
                  ),
          ),
          const ChatComposer(),
        ],
      ),
    );
  }
}
