import 'quiz_question.dart';

QuizQuestion? extractStreamingQuiz(Map<String, dynamic> metadata) {
  if (metadata['call_kind'] != 'quiz_question_emitted') return null;
  final qaPair = _stringMap(metadata['qa_pair']);
  if (qaPair == null) return null;
  try {
    return _normalizedQuestion(QuizQuestion.fromJson(qaPair));
  } on FormatException {
    return null;
  }
}

int? streamingQuestionIndex(Map<String, dynamic> metadata) {
  final value = metadata['question_index'];
  return switch (value) {
    int number => number,
    num number => number.toInt(),
    _ => int.tryParse('$value'),
  };
}

List<QuizQuestion> extractQuizFromResult(Map<String, dynamic> metadata) {
  final summary = _stringMap(metadata['summary']);
  final rawResults = summary?['results'];
  if (rawResults is! Iterable) return const <QuizQuestion>[];

  final questions = <QuizQuestion>[];
  final seen = <String>{};
  for (final raw in rawResults) {
    final item = _stringMap(raw);
    if (item == null) continue;
    try {
      final question = _normalizedQuestion(QuizQuestion.fromJson(item));
      if (seen.add(question.deduplicationKey)) questions.add(question);
    } on FormatException {
      // One malformed question must not hide valid questions in the result.
    }
  }
  return List<QuizQuestion>.unmodifiable(questions);
}

List<QuizQuestion> extractQuizFromEvents(Iterable<Object?> events) {
  final streamed = <int, QuizQuestion>{};
  final unordered = <QuizQuestion>[];
  List<QuizQuestion>? authoritative;

  for (final raw in events) {
    final event = _stringMap(raw);
    if (event == null) continue;
    final metadata = _stringMap(event['metadata']) ?? const <String, dynamic>{};
    if (event['type'] == 'result') {
      final parsed = extractQuizFromResult(metadata);
      if (parsed.isNotEmpty) authoritative = parsed;
      continue;
    }
    if (event['type'] != 'content') continue;
    final question = extractStreamingQuiz(metadata);
    if (question == null) continue;
    final index = streamingQuestionIndex(metadata);
    if (index == null) {
      unordered.add(question);
    } else {
      streamed[index] = question;
    }
  }
  if (authoritative != null) return authoritative;

  final ordered = streamed.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return _deduplicate(<QuizQuestion>[
    ...ordered.map((entry) => entry.value),
    ...unordered,
  ]);
}

String normalizeQuestionType(String raw) {
  return switch (raw.trim().toLowerCase().replaceAll('-', '_')) {
    'multiple_choice' || 'single_choice' || 'true_false' || 'mcq' => 'choice',
    'conceptual' || 'concept_question' => 'concept',
    'fill_blank' || 'fill_in_the_blank' => 'fill_in_blank',
    'short' || 'shortanswer' => 'short_answer',
    'essay' || 'long_answer' || 'proof' => 'written',
    'programming' || 'code' => 'coding',
    final normalized => normalized,
  };
}

QuizQuestion _normalizedQuestion(QuizQuestion question) {
  return QuizQuestion(
    id: question.id,
    question: question.question,
    questionType: normalizeQuestionType(question.questionType),
    options: question.options,
    correctAnswer: question.correctAnswer,
    explanation: question.explanation,
    difficulty: question.difficulty,
  );
}

List<QuizQuestion> _deduplicate(List<QuizQuestion> questions) {
  final seen = <String>{};
  return List<QuizQuestion>.unmodifiable(
    questions.where((question) => seen.add(question.deduplicationKey)),
  );
}

Map<String, dynamic>? _stringMap(Object? value) {
  if (value is! Map) return null;
  return value.map((key, item) => MapEntry(key.toString(), item));
}
