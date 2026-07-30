import 'package:deeptutor_mobile/features/auth/login_page.dart';
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

Widget buildLoginPage(MemorySecureStore store) {
  return ProviderScope(
    overrides: [secureKeyValueStoreProvider.overrideWithValue(store)],
    child: const MaterialApp(home: LoginPage()),
  );
}

void main() {
  testWidgets('renders labelled fields and an accessible login action', (
    tester,
  ) async {
    await tester.pumpWidget(buildLoginPage(MemorySecureStore()));
    await tester.pump();

    expect(find.text('连接 DeepTutor'), findsOneWidget);
    expect(find.text('服务器地址'), findsOneWidget);
    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
    expect(find.byTooltip('显示密码'), findsOneWidget);
  });

  testWidgets('reports invalid server URLs without starting a request', (
    tester,
  ) async {
    await tester.pumpWidget(buildLoginPage(MemorySecureStore()));
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextFormField, '服务器地址'),
      'ftp://example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '用户名'),
      'learner',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '密码'),
      'password',
    );
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pump();

    expect(find.text('请输入有效的 HTTP 或 HTTPS 服务器地址'), findsOneWidget);
  });
}
