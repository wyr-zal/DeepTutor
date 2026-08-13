import 'package:deeptutor_mobile/models/think_segments.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitThinking', () {
    test('returns body untouched when there is no think tag', () {
      final result = splitThinking('Hello **world**');
      expect(result.hasThinking, isFalse);
      expect(result.thinking, isEmpty);
      expect(result.thinkingClosed, isTrue);
      expect(result.body, 'Hello **world**');
    });

    test('extracts a closed think block', () {
      final result = splitThinking('<think>reasoning here</think>Answer.');
      expect(result.hasThinking, isTrue);
      expect(result.thinking, 'reasoning here');
      expect(result.thinkingClosed, isTrue);
      expect(result.body, 'Answer.');
    });

    test('handles <thinking> alias and attributes', () {
      final result =
          splitThinking('<thinking duration="3s">step</thinking>done');
      expect(result.thinking, 'step');
      expect(result.thinkingClosed, isTrue);
      expect(result.body, 'done');
    });

    test('marks an unclosed think block as still streaming', () {
      final result = splitThinking('<think>partial reasoning');
      expect(result.hasThinking, isTrue);
      expect(result.thinking, 'partial reasoning');
      expect(result.thinkingClosed, isFalse);
      expect(result.body, isEmpty);
    });

    test('tolerates backtick-escaped tags', () {
      final result = splitThinking('`<think>`foo`</think>`bar');
      expect(result.thinking, 'foo');
      expect(result.body, 'bar');
    });

    test('ignores think tags inside fenced code blocks', () {
      const input = '```\n<think>not thinking</think>\n```\nreal body';
      final result = splitThinking(input);
      expect(result.hasThinking, isFalse);
      expect(result.body, contains('<think>not thinking</think>'));
    });

    test('joins multiple think blocks and keeps surrounding text', () {
      final result =
          splitThinking('a<think>one</think>b<think>two</think>c');
      expect(result.thinking, 'one\n\ntwo');
      expect(result.body, 'abc');
      expect(result.thinkingClosed, isTrue);
    });
  });
}
