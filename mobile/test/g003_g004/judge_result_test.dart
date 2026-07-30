import 'package:deeptutor_mobile/models/judge_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('infers only a leading verdict marker or verdict phrase', () {
    expect(JudgeResult.inferVerdict('✅ 正确：推导完整'), JudgeVerdict.correct);
    expect(
      JudgeResult.inferVerdict('⚠️ 部分正确：少了单位'),
      JudgeVerdict.partiallyCorrect,
    );
    expect(JudgeResult.inferVerdict('❌ 不正确：符号错误'), JudgeVerdict.incorrect);
    expect(
      JudgeResult.inferVerdict('你提到了“正确”这个词，但服务端没有给出结论。'),
      JudgeVerdict.unknown,
    );
  });

  test('preserves raw judge text across JSON round trip', () {
    final result = JudgeResult.fromText(
      '服务端原始返回，不伪造 marker。',
      completedAt: DateTime.utc(2026, 7, 28, 10),
    );
    final restored = JudgeResult.fromJson(result.toJson());

    expect(restored.text, result.text);
    expect(restored.verdict, JudgeVerdict.unknown);
    expect(restored.completedAt, result.completedAt);
  });
}
