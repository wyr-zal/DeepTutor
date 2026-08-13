import 'package:deeptutor_mobile/features/auth/login_page.dart';
import 'package:deeptutor_mobile/config/app_config.dart';
import 'package:deeptutor_mobile/services/auth_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

Widget buildLoginPage(
  MemorySecureStore store, {
  AppConnectionConfig config = const AppConnectionConfig(
    fixedServerUrl: '',
    manualServerEntryEnabled: true,
  ),
}) {
  return ProviderScope(
    overrides: [
      secureKeyValueStoreProvider.overrideWithValue(store),
      appConnectionConfigProvider.overrideWithValue(config),
    ],
    child: const MaterialApp(home: LoginPage()),
  );
}

void main() {
  testWidgets('debug entry initially asks only for a development server', (
    tester,
  ) async {
    await tester.pumpWidget(buildLoginPage(MemorySecureStore()));
    await tester.pump();

    expect(find.text('连接 DeepTutor'), findsOneWidget);
    expect(find.text('开发服务器地址'), findsOneWidget);
    expect(find.text('用户名'), findsNothing);
    expect(find.text('密码'), findsNothing);
    expect(find.widgetWithText(FilledButton, '连接'), findsOneWidget);
  });

  testWidgets('reports invalid server URLs without starting a request', (
    tester,
  ) async {
    await tester.pumpWidget(buildLoginPage(MemorySecureStore()));
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextFormField, '开发服务器地址'),
      'ftp://example.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, '连接'));
    await tester.pump();

    expect(find.text('请输入有效的 HTTP 或 HTTPS 服务器地址'), findsOneWidget);
  });

  testWidgets('fixed server login hides all server address controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildLoginPage(
        MemorySecureStore(),
        config: const AppConnectionConfig(
          fixedServerUrl: 'https://tutor.example.com',
          manualServerEntryEnabled: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('登录 DeepTutor'), findsOneWidget);
    expect(find.text('开发服务器地址'), findsNothing);
    expect(find.text('更换开发服务器'), findsNothing);
    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.byTooltip('显示密码'), findsOneWidget);
  });

  testWidgets('production without a fixed server shows configuration error', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildLoginPage(
        MemorySecureStore(),
        config: const AppConnectionConfig(
          fixedServerUrl: '',
          manualServerEntryEnabled: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('DeepTutor 尚未配置'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });
}
