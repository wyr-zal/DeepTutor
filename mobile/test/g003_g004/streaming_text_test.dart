import 'package:deeptutor_mobile/models/judge_result.dart';
import 'package:deeptutor_mobile/widgets/streaming_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows raw text and an honest unknown fallback', (tester) async {
    final result = JudgeResult.fromText('继续努力，检查第二步。');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingText(text: result.text, result: result),
        ),
      ),
    );

    expect(find.text('继续努力，检查第二步。'), findsOneWidget);
    expect(find.text('未从返回文字识别判定状态'), findsOneWidget);
    expect(find.textContaining('✅'), findsNothing);
  });
}
