enum JudgeVerdict { correct, partiallyCorrect, incorrect, unknown }

class JudgeResult {
  const JudgeResult({
    required this.text,
    required this.verdict,
    required this.completedAt,
  });

  factory JudgeResult.fromText(String text, {DateTime? completedAt}) {
    return JudgeResult(
      text: text,
      verdict: inferVerdict(text),
      completedAt: completedAt ?? DateTime.now().toUtc(),
    );
  }

  factory JudgeResult.fromJson(Map<String, dynamic> json) {
    final text = json['text']?.toString() ?? '';
    final savedVerdict = json['verdict']?.toString();
    return JudgeResult(
      text: text,
      verdict: JudgeVerdict.values.firstWhere(
        (value) => value.name == savedVerdict,
        orElse: () => inferVerdict(text),
      ),
      completedAt:
          DateTime.tryParse(json['completed_at']?.toString() ?? '')?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String text;
  final JudgeVerdict verdict;
  final DateTime completedAt;

  bool get hasRecognizedVerdict => verdict != JudgeVerdict.unknown;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'text': text,
        'verdict': verdict.name,
        'completed_at': completedAt.toUtc().toIso8601String(),
      };

  static JudgeVerdict inferVerdict(String text) {
    final normalized = text.trimLeft().toLowerCase();
    if (normalized.isEmpty) return JudgeVerdict.unknown;

    if (normalized.startsWith('✅') ||
        normalized.startsWith('正确') ||
        normalized.startsWith('correct')) {
      return JudgeVerdict.correct;
    }
    if (normalized.startsWith('⚠️') ||
        normalized.startsWith('⚠') ||
        normalized.startsWith('部分正确') ||
        normalized.startsWith('partially correct')) {
      return JudgeVerdict.partiallyCorrect;
    }
    if (normalized.startsWith('❌') ||
        normalized.startsWith('不正确') ||
        normalized.startsWith('错误') ||
        normalized.startsWith('incorrect')) {
      return JudgeVerdict.incorrect;
    }
    return JudgeVerdict.unknown;
  }
}
