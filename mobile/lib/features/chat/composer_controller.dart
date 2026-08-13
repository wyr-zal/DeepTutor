import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chat_message.dart';
import '../../models/deep_question_config.dart';

class ComposerState {
  const ComposerState({
    this.capability = ChatCapability.chat,
    this.selectedKnowledgeBases = const <String>{},
    this.quizConfig = const DeepQuestionFormConfig.initial(),
  });

  final ChatCapability capability;
  final Set<String> selectedKnowledgeBases;
  final DeepQuestionFormConfig quizConfig;

  ComposerState copyWith({
    ChatCapability? capability,
    Set<String>? selectedKnowledgeBases,
    DeepQuestionFormConfig? quizConfig,
  }) {
    return ComposerState(
      capability: capability ?? this.capability,
      selectedKnowledgeBases:
          selectedKnowledgeBases ?? this.selectedKnowledgeBases,
      quizConfig: quizConfig ?? this.quizConfig,
    );
  }
}

final composerControllerProvider =
    NotifierProvider<ComposerController, ComposerState>(ComposerController.new);

class ComposerController extends Notifier<ComposerState> {
  @override
  ComposerState build() => const ComposerState();

  void selectCapability(ChatCapability capability) {
    state = state.copyWith(capability: capability);
  }

  void toggleKnowledgeBase(String name) {
    final selected = Set<String>.from(state.selectedKnowledgeBases);
    selected.contains(name) ? selected.remove(name) : selected.add(name);
    state = state.copyWith(selectedKnowledgeBases: selected);
  }

  void replaceKnowledgeBases(Set<String> names) {
    state = state.copyWith(selectedKnowledgeBases: Set<String>.from(names));
  }

  void updateQuizConfig(DeepQuestionFormConfig config) {
    state = state.copyWith(quizConfig: config);
  }
}
