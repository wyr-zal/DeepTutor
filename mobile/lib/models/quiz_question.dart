class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.question,
    required this.questionType,
    this.options = const <String, String>{},
    required this.correctAnswer,
    required this.explanation,
    this.difficulty = '',
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    final nested = json['qa_pair'];
    final source = nested is Map
        ? nested.map((key, value) => MapEntry(key.toString(), value))
        : json;
    final question = _string(source['question']);
    if (question.isEmpty) {
      throw const FormatException('Quiz question text is missing.');
    }

    return QuizQuestion(
      id: _string(source['question_id'] ?? source['id']),
      question: question,
      questionType: _string(source['question_type'] ?? source['type']),
      options: _options(source['options']),
      correctAnswer: _answer(source['correct_answer'] ?? source['answer']),
      explanation: _string(source['explanation']),
      difficulty: _string(source['difficulty']),
    );
  }

  final String id;
  final String question;
  final String questionType;
  final Map<String, String> options;
  final String correctAnswer;
  final String explanation;
  final String difficulty;

  String get deduplicationKey {
    if (id.trim().isNotEmpty) return 'id:${id.trim()}';
    return <String>[
      question.trim().toLowerCase(),
      questionType.trim().toLowerCase(),
      ...options.entries.map(
        (entry) =>
            '${entry.key.trim().toLowerCase()}=${entry.value.trim().toLowerCase()}',
      ),
    ].join('\u001f');
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'question_id': id,
        'question': question,
        'question_type': questionType,
        'options': options,
        'correct_answer': correctAnswer,
        'explanation': explanation,
        'difficulty': difficulty,
      };

  /// Whether this is a single-choice question with usable options.
  bool get isMultipleChoice => questionType == 'choice' && options.isNotEmpty;

  /// Types the client can grade locally without an AI judge: choice, concept
  /// (true/false) and fill_in_blank — mirrors the web `isAutoGradable`.
  bool get isAutoGradable =>
      isMultipleChoice ||
      questionType == 'concept' ||
      questionType == 'fill_in_blank';

  /// Resolve the canonical option key ("A"/"B"/…) for [correctAnswer],
  /// tolerating an answer given either as the key or as the option text.
  String get correctChoiceKey {
    final correct = correctAnswer.trim();
    if (correct.isEmpty || options.isEmpty) return '';
    final direct = correct.toUpperCase();
    if (options.containsKey(direct)) return direct;
    final lowerAnswer = correct.toLowerCase();
    for (final entry in options.entries) {
      if (entry.value.trim().toLowerCase() == lowerAnswer) {
        return entry.key.toUpperCase();
      }
    }
    // Fall back to the leading letter (e.g. "B. foo" -> "B").
    return correct.substring(0, 1).toUpperCase();
  }

  /// Canonical "true"/"false" answer for concept questions, or '' if unknown.
  String get correctConceptAnswer {
    final normalized = correctAnswer.trim().toLowerCase();
    if (normalized == 'true') return 'true';
    if (normalized == 'false') return 'false';
    return '';
  }

  /// Local pass/fail check for auto-gradable types. [selected] carries the
  /// option key or "true"/"false"; [typed] carries free-text answers.
  bool isAnswerCorrectLocally({String selected = '', String typed = ''}) {
    final correct = correctAnswer.trim();
    if (isMultipleChoice) {
      final user = selected.trim().toUpperCase();
      if (user.isEmpty) return false;
      return user == correctChoiceKey ||
          user == correct.toUpperCase() ||
          (correct.isNotEmpty && user == correct.substring(0, 1).toUpperCase());
    }
    if (questionType == 'concept') {
      final user = selected.trim().toLowerCase();
      return user.isNotEmpty && user == correctConceptAnswer;
    }
    // fill_in_blank
    final user = typed.trim();
    return user.isNotEmpty && user.toLowerCase() == correct.toLowerCase();
  }

  static String _answer(Object? value) {
    if (value is Iterable) {
      return value.map((item) => item.toString()).join(', ');
    }
    return _string(value);
  }

  static String _string(Object? value) => value?.toString().trim() ?? '';

  static Map<String, String> _options(Object? value) {
    if (value is Map) {
      final result = <String, String>{};
      for (final entry in value.entries) {
        final key = entry.key.toString().trim().toUpperCase();
        final text = entry.value.toString().trim();
        if (key.isNotEmpty && text.isNotEmpty) result[key] = text;
      }
      return Map<String, String>.unmodifiable(result);
    }
    if (value is Iterable) {
      final result = <String, String>{};
      var index = 0;
      for (final item in value) {
        final text = item.toString().trim();
        if (text.isEmpty) continue;
        result[String.fromCharCode(65 + index)] = text;
        index++;
      }
      return Map<String, String>.unmodifiable(result);
    }
    return const <String, String>{};
  }
}
