import 'package:deeptutor_mobile/models/quiz_question.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the backend qa_pair shape', () {
    final question = QuizQuestion.fromJson(<String, Object?>{
      'qa_pair': <String, Object?>{
        'question_id': 'q-1',
        'question': '2 + 2 = ?',
        'question_type': 'choice',
        'options': <String, String>{'A': '3', 'B': '4'},
        'correct_answer': '4',
        'explanation': 'Basic addition.',
        'difficulty': 'easy',
      },
    });

    expect(question.id, 'q-1');
    expect(question.questionType, 'choice');
    expect(question.options, <String, String>{'A': '3', 'B': '4'});
    expect(question.correctAnswer, '4');
    expect(question.deduplicationKey, 'id:q-1');
  });

  test('uses stable content deduplication when id is absent', () {
    const first = QuizQuestion(
      id: '',
      question: '  What is Dart? ',
      questionType: 'Concept',
      options: <String, String>{},
      correctAnswer: 'A language',
      explanation: '',
    );
    const second = QuizQuestion(
      id: '',
      question: 'what is dart?',
      questionType: 'concept',
      options: <String, String>{},
      correctAnswer: 'A language',
      explanation: '',
    );

    expect(first.deduplicationKey, second.deduplicationKey);
  });
}
