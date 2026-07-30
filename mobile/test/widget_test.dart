import 'package:deeptutor_mobile/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DeepTutor theme exposes the mobile brand contract', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDeepTutorTheme(Brightness.light),
        home: const Scaffold(body: Text('DeepTutor')),
      ),
    );

    final context = tester.element(find.text('DeepTutor'));
    expect(Theme.of(context).colorScheme.primary, const Color(0xFF2563EB));
    expect(find.text('DeepTutor'), findsOneWidget);
  });
}
