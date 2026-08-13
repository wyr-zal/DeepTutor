import 'package:deeptutor_mobile/models/deep_question_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('custom config mirrors the strict backend contract', () {
    const config = DeepQuestionFormConfig(
      numQuestions: 5,
      difficulty: 'auto',
      questionTypes: <String>['choice', 'short_answer'],
      perTypeCounts: <String, int>{'choice': 3, 'short_answer': 2},
      paperPath: 'must-not-leak',
      maxQuestions: 99,
    );

    expect(buildQuizConfig(config), <String, Object?>{
      'mode': 'custom',
      'num_questions': 5,
      'difficulty': '',
      'question_types': <String>['choice', 'short_answer'],
      'per_type_counts': <String, int>{'choice': 3, 'short_answer': 2},
    });
  });

  test('invalid per-type counts are replaced with an empty object', () {
    const config = DeepQuestionFormConfig(
      numQuestions: 3,
      questionTypes: <String>['choice', 'concept'],
      perTypeCounts: <String, int>{'choice': 1, 'concept': 1},
    );

    expect(buildQuizConfig(config)['per_type_counts'], <String, int>{});
  });

  test('mimic config sends only paper fields', () {
    const config = DeepQuestionFormConfig(
      mode: DeepQuestionMode.mimic,
      paperPath: '  paper-01  ',
      maxQuestions: 12,
      numQuestions: 40,
      difficulty: 'hard',
    );

    expect(buildQuizConfig(config), <String, Object?>{
      'mode': 'mimic',
      'paper_path': 'paper-01',
      'max_questions': 12,
    });
  });

  test('validates documented question bounds', () {
    expect(
      () => buildQuizConfig(const DeepQuestionFormConfig(numQuestions: 0)),
      throwsRangeError,
    );
    expect(
      () => buildQuizConfig(
        const DeepQuestionFormConfig(
          mode: DeepQuestionMode.mimic,
          maxQuestions: 101,
        ),
      ),
      throwsRangeError,
    );
  });
}
