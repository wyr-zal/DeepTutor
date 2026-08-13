enum DeepQuestionMode { custom, mimic }

const List<String> kQuizQuestionTypes = <String>[
  'choice',
  'concept',
  'fill_in_blank',
  'short_answer',
  'written',
  'coding',
];

const Map<String, String> kQuizQuestionTypeLabels = <String, String>{
  'choice': '选择题',
  'concept': '概念题',
  'fill_in_blank': '填空题',
  'short_answer': '简答题',
  'written': '论述题',
  'coding': '编程题',
};

class DeepQuestionFormConfig {
  const DeepQuestionFormConfig({
    this.mode = DeepQuestionMode.custom,
    this.numQuestions = 3,
    this.difficulty = 'auto',
    this.questionTypes = const <String>[],
    this.perTypeCounts = const <String, int>{},
    this.paperPath = '',
    this.maxQuestions = 10,
  });

  const DeepQuestionFormConfig.initial() : this();

  final DeepQuestionMode mode;
  final int numQuestions;
  final String difficulty;
  final List<String> questionTypes;
  final Map<String, int> perTypeCounts;
  final String paperPath;
  final int maxQuestions;

  DeepQuestionFormConfig copyWith({
    DeepQuestionMode? mode,
    int? numQuestions,
    String? difficulty,
    List<String>? questionTypes,
    Map<String, int>? perTypeCounts,
    String? paperPath,
    int? maxQuestions,
  }) {
    return DeepQuestionFormConfig(
      mode: mode ?? this.mode,
      numQuestions: numQuestions ?? this.numQuestions,
      difficulty: difficulty ?? this.difficulty,
      questionTypes: questionTypes ?? this.questionTypes,
      perTypeCounts: perTypeCounts ?? this.perTypeCounts,
      paperPath: paperPath ?? this.paperPath,
      maxQuestions: maxQuestions ?? this.maxQuestions,
    );
  }
}

Map<String, dynamic> buildQuizConfig(DeepQuestionFormConfig config) {
  if (config.mode == DeepQuestionMode.mimic) {
    if (config.maxQuestions < 1 || config.maxQuestions > 100) {
      throw RangeError.range(config.maxQuestions, 1, 100, 'maxQuestions');
    }
    return <String, dynamic>{
      'mode': 'mimic',
      'paper_path': config.paperPath.trim(),
      'max_questions': config.maxQuestions,
    };
  }

  if (config.numQuestions < 1 || config.numQuestions > 50) {
    throw RangeError.range(config.numQuestions, 1, 50, 'numQuestions');
  }
  final questionTypes = config.questionTypes
      .where(kQuizQuestionTypes.contains)
      .toSet()
      .toList(growable: false);
  final countTotal = config.perTypeCounts.values.fold<int>(
    0,
    (total, count) => total + count,
  );
  final countsAreValid = questionTypes.length >= 2 &&
      config.perTypeCounts.isNotEmpty &&
      config.perTypeCounts.keys.every(questionTypes.contains) &&
      config.perTypeCounts.values.every((count) => count >= 0) &&
      countTotal == config.numQuestions;

  return <String, dynamic>{
    'mode': 'custom',
    'num_questions': config.numQuestions,
    'difficulty': config.difficulty == 'auto' ? '' : config.difficulty,
    'question_types': questionTypes,
    'per_type_counts': countsAreValid
        ? Map<String, int>.from(config.perTypeCounts)
        : <String, int>{},
  };
}

String summarizeQuizConfig(DeepQuestionFormConfig config) {
  if (config.mode == DeepQuestionMode.mimic) {
    final paper =
        config.paperPath.trim().isEmpty ? '未选试卷' : config.paperPath.trim();
    return '模仿试卷 · $paper · 最多 ${config.maxQuestions} 题';
  }
  final typeSummary = switch (config.questionTypes.length) {
    0 => '题型自动',
    1 => kQuizQuestionTypeLabels[config.questionTypes.first] ?? '1 种题型',
    final count => '$count 种题型',
  };
  final difficulty = switch (config.difficulty) {
    'easy' => '简单',
    'medium' => '中等',
    'hard' => '困难',
    _ => '难度自动',
  };
  return '自定义 · ${config.numQuestions} 题 · $difficulty · $typeSummary';
}
