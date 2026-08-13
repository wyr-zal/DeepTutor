import 'package:deeptutor_mobile/features/chat/widgets/chat_message_list.dart';
import 'package:deeptutor_mobile/models/chat_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'streaming follows only after the user reaches the latest position',
    (tester) async {
      var messages = <ChatMessage>[
        const ChatMessage(
          id: 'assistant-1',
          role: ChatRole.assistant,
          textBuffer: '开始回答',
          streaming: true,
        ),
      ];
      late StateSetter rebuild;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 360,
              child: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return ChatMessageList(
                    messages: messages,
                    onUnauthorized: () {},
                    onAnswerStateChanged: (_, __, ___) {},
                  );
                },
              ),
            ),
          ),
        ),
      );

      ScrollPosition position() {
        final scrollable = find.descendant(
          of: find.byKey(const ValueKey('chat-message-list')),
          matching: find.byType(Scrollable),
        );
        return tester.state<ScrollableState>(scrollable).position;
      }

      Future<void> finishScrollAnimation() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 250));
      }

      // Growing from a short answer into an overflowing stream must not take
      // control before the user has explicitly moved to the latest content.
      rebuild(() {
        messages = <ChatMessage>[
          messages.single.copyWith(
            textBuffer: List<String>.generate(
              80,
              (index) => '流式回答第 $index 行',
            ).join('\n\n'),
          ),
        ];
      });
      await finishScrollAnimation();

      expect(position().maxScrollExtent, greaterThan(0));
      expect(position().pixels, 0);

      // Reaching the newest content opts in to following subsequent chunks.
      await tester.drag(
        find.byKey(const ValueKey('chat-message-list')),
        const Offset(0, -10000),
      );
      await finishScrollAnimation();
      expect(position().extentAfter, lessThanOrEqualTo(1));

      rebuild(() {
        messages = <ChatMessage>[
          messages.single.copyWith(
            textBuffer: '${messages.single.textBuffer}\n\n最新正文片段',
          ),
        ];
      });
      await finishScrollAnimation();
      expect(position().extentAfter, lessThanOrEqualTo(1));

      // Moving back to older content immediately opts out, for both thinking
      // chunks and regular answer chunks.
      await tester.drag(
        find.byKey(const ValueKey('chat-message-list')),
        const Offset(0, 220),
      );
      await finishScrollAnimation();
      final readingOffset = position().pixels;
      expect(position().extentAfter, greaterThan(48));

      rebuild(() {
        messages = <ChatMessage>[
          messages.single.copyWith(
            thinkingBuffer: List<String>.generate(
              12,
              (index) => '思考片段 $index',
            ).join('\n\n'),
            textBuffer: '${messages.single.textBuffer}\n\n又一段正文',
          ),
        ];
      });
      await finishScrollAnimation();

      expect(position().pixels, closeTo(readingOffset, 1));
      expect(position().extentAfter, greaterThan(48));
    },
  );
}
