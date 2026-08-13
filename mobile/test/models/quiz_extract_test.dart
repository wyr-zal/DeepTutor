import 'package:deeptutor_mobile/models/quiz_extract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const firstQa = <String, Object?>{
    'question_id': 'q1',
    'question': '2 + 2 = ?',
    'question_type': 'multiple_choice',
    'options': <String, String>{'A': '3', 'B': '4'},
    'correct_answer': 'B',
    'explanation': '基础加法。',
  };

  test('extracts a streaming quiz question and normalizes its type', () {
    final metadata = <String, Object?>{
      'call_kind': 'quiz_question_emitted',
      'question_index': 2,
      'qa_pair': firstQa,
    };

    final question = extractStreamingQuiz(metadata);

    expect(question?.id, 'q1');
    expect(question?.questionType, 'choice');
    expect(streamingQuestionIndex(metadata), 2);
  });

  test('extracts authoritative summary results and skips malformed rows', () {
    final questions = extractQuizFromResult(<String, Object?>{
      'summary': <String, Object?>{
        'results': <Object?>[
          <String, Object?>{'qa_pair': firstQa},
          <String, Object?>{
            'qa_pair': <String, Object?>{'question_id': 'broken'},
          },
          <String, Object?>{'qa_pair': firstQa},
        ],
      },
    });

    expect(questions, hasLength(1));
    expect(questions.single.id, 'q1');
  });

  test('result events override streamed questions in session history', () {
    final questions = extractQuizFromEvents(<Object?>[
      <String, Object?>{
        'type': 'content',
        'metadata': <String, Object?>{
          'call_kind': 'quiz_question_emitted',
          'question_index': 0,
          'qa_pair': firstQa,
        },
      },
      <String, Object?>{
        'type': 'result',
        'metadata': <String, Object?>{
          'summary': <String, Object?>{
            'results': <Object?>[
              <String, Object?>{
                'qa_pair': <String, Object?>{
                  'question_id': 'q-final',
                  'question': '最终题目',
                  'question_type': 'short_answer',
                  'correct_answer': '最终答案',
                  'explanation': '最终解析',
                },
              },
            ],
          },
        },
      },
    ]);

    expect(questions, hasLength(1));
    expect(questions.single.id, 'q-final');
  });

  test('returns no question for unrelated content events', () {
    expect(
      extractStreamingQuiz(<String, Object?>{'call_kind': 'assistant_text'}),
      isNull,
    );
  });
}
