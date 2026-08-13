import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/auth_session.dart';
import '../../services/local_chat_store.dart';

final localChatStoreProvider = Provider.family<LocalChatStore, AuthSession>(
  (ref, session) {
    final store = LocalChatStore.scoped(
      serverUrl: session.baseUrl,
      userId: session.user.id,
    );
    ref.onDispose(() => unawaited(store.close()));
    return store;
  },
);
