import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/question_ws.dart';
import '../../models/quiz_question.dart';
import '../../services/auth_store.dart';

final questionGenerationGatewayProvider =
    FutureProvider<QuestionGenerationGateway>((ref) async {
  final authStore = ref.watch(authStoreProvider);
  final baseUrl = (await authStore.readBaseUrl())?.trim();
  if (baseUrl == null || baseUrl.isEmpty) {
    throw const QuestionConnectionException('尚未配置服务器，请重新登录。');
  }
  return QuestionWsClient(
    baseUrl: baseUrl,
    tokenLoader: authStore.readAccessToken,
  );
});

enum QuizGenerationPhase { idle, connecting, generating, complete, error }

class QuizGenerationState {
  const QuizGenerationState({
    this.phase = QuizGenerationPhase.idle,
    this.questions = const <QuizQuestion>[],
    this.message = '',
    this.taskId,
    this.requested = 0,
    this.completed = 0,
    this.failed = 0,
    this.unauthorized = false,
  });

  final QuizGenerationPhase phase;
  final List<QuizQuestion> questions;
  final String message;
  final String? taskId;
  final int requested;
  final int completed;
  final int failed;
  final bool unauthorized;

  bool get isLoading =>
      phase == QuizGenerationPhase.connecting ||
      phase == QuizGenerationPhase.generating;

  QuizGenerationState copyWith({
    QuizGenerationPhase? phase,
    List<QuizQuestion>? questions,
    String? message,
    String? taskId,
    int? requested,
    int? completed,
    int? failed,
    bool? unauthorized,
  }) {
    return QuizGenerationState(
      phase: phase ?? this.phase,
      questions: questions ?? this.questions,
      message: message ?? this.message,
      taskId: taskId ?? this.taskId,
      requested: requested ?? this.requested,
      completed: completed ?? this.completed,
      failed: failed ?? this.failed,
      unauthorized: unauthorized ?? this.unauthorized,
    );
  }
}

final quizGenerationControllerProvider =
    AutoDisposeNotifierProvider<QuizGenerationController, QuizGenerationState>(
  QuizGenerationController.new,
);

class QuizGenerationController
    extends AutoDisposeNotifier<QuizGenerationState> {
  StreamSubscription<QuestionStreamEvent>? _subscription;
  Completer<void>? _runDone;
  QuizGenerationRequest? _lastRequest;
  bool _disposed = false;

  @override
  QuizGenerationState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      unawaited(_subscription?.cancel());
      if (!(_runDone?.isCompleted ?? true)) _runDone!.complete();
    });
    return const QuizGenerationState();
  }

  Future<void> start(QuizGenerationRequest request) async {
    _lastRequest = request;
    await _subscription?.cancel();
    if (!(_runDone?.isCompleted ?? true)) _runDone!.complete();
    if (_disposed) return;
    state = QuizGenerationState(
      phase: QuizGenerationPhase.connecting,
      message: '正在连接出题服务…',
      requested: request.count,
    );

    try {
      final gateway = await ref.read(questionGenerationGatewayProvider.future);
      if (_disposed) return;
      final done = Completer<void>();
      _runDone = done;
      _subscription = gateway.generate(request).listen(
        _handleEvent,
        onError: (Object error, StackTrace stackTrace) {
          if (!_disposed) {
            _setError(
              _readableError(error),
              unauthorized: error is QuestionUnauthorizedException,
            );
          }
          if (!done.isCompleted) done.complete();
        },
        onDone: () {
          if (!_disposed && state.isLoading) {
            _setError('连接提前结束，请重试。');
          }
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: false,
      );
      await done.future;
      if (identical(_runDone, done)) _runDone = null;
    } catch (error) {
      if (!_disposed) {
        _setError(
          _readableError(error),
          unauthorized: error is QuestionUnauthorizedException,
        );
      }
    }
  }

  Future<void> retry() async {
    final request = _lastRequest;
    if (request != null) await start(request);
  }

  Future<void> cancel() async {
    await _subscription?.cancel();
    _subscription = null;
    if (!(_runDone?.isCompleted ?? true)) _runDone!.complete();
    if (!_disposed && state.isLoading) {
      state = state.copyWith(
        phase: QuizGenerationPhase.error,
        message: '已停止生成。',
      );
    }
  }

  void _handleEvent(QuestionStreamEvent event) {
    if (_disposed) return;
    switch (event.type) {
      case QuestionStreamEventType.connected:
      case QuestionStreamEventType.status:
      case QuestionStreamEventType.progress:
        state = state.copyWith(
          phase: QuizGenerationPhase.generating,
          message: event.message.isEmpty ? '正在生成题目…' : event.message,
        );
        return;
      case QuestionStreamEventType.taskId:
        state = state.copyWith(taskId: event.taskId);
        return;
      case QuestionStreamEventType.question:
        final question = event.question;
        if (question == null) return;
        final byKey = <String, QuizQuestion>{
          for (final item in state.questions) item.deduplicationKey: item,
          question.deduplicationKey: question,
        };
        state = state.copyWith(
          phase: QuizGenerationPhase.generating,
          questions: List<QuizQuestion>.unmodifiable(byKey.values),
          completed: byKey.length,
          message: '已生成 ${byKey.length}/${state.requested} 道题',
        );
        return;
      case QuestionStreamEventType.batchSummary:
        state = state.copyWith(
          requested: event.requested ?? state.requested,
          completed: event.completed ?? state.questions.length,
          failed: event.failed ?? state.failed,
        );
        return;
      case QuestionStreamEventType.result:
        return;
      case QuestionStreamEventType.complete:
        state = state.copyWith(
          phase: QuizGenerationPhase.complete,
          completed: state.questions.length,
          message: state.questions.isEmpty ? '未生成可用题目。' : '题目生成完成',
        );
        return;
      case QuestionStreamEventType.error:
        _setError(event.message);
        return;
    }
  }

  void _setError(String message, {bool unauthorized = false}) {
    state = state.copyWith(
      phase: QuizGenerationPhase.error,
      message: message,
      unauthorized: unauthorized,
    );
  }

  static String _readableError(Object error) {
    if (error is QuestionConnectionException) return error.message;
    return '题目生成失败，请检查网络后重试。';
  }
}
