import 'judge_result.dart';
import 'quiz_question.dart';

class QuizAttempt {
  const QuizAttempt({
    required this.id,
    required this.question,
    required this.userAnswer,
    required this.result,
    required this.createdAt,
  });

  factory QuizAttempt.create({
    required QuizQuestion question,
    required String userAnswer,
    required JudgeResult result,
    DateTime? createdAt,
  }) {
    final timestamp = (createdAt ?? DateTime.now()).toUtc();
    return QuizAttempt(
      id: '${timestamp.microsecondsSinceEpoch}-${question.id}',
      question: question,
      userAnswer: userAnswer,
      result: result,
      createdAt: timestamp,
    );
  }

  factory QuizAttempt.fromJson(Map<String, dynamic> json) {
    final questionJson = json['question'];
    final resultJson = json['result'];
    if (questionJson is! Map || resultJson is! Map) {
      throw const FormatException('Invalid quiz attempt payload.');
    }
    return QuizAttempt(
      id: json['id']?.toString() ?? '',
      question: QuizQuestion.fromJson(
        questionJson.map((key, value) => MapEntry(key.toString(), value)),
      ),
      userAnswer: json['user_answer']?.toString() ?? '',
      result: JudgeResult.fromJson(
        resultJson.map((key, value) => MapEntry(key.toString(), value)),
      ),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '')?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String id;
  final QuizQuestion question;
  final String userAnswer;
  final JudgeResult result;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'question': question.toJson(),
        'user_answer': userAnswer,
        'result': result.toJson(),
        'created_at': createdAt.toUtc().toIso8601String(),
      };
}
