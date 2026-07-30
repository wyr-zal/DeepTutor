import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/judge_result.dart';

class StreamingText extends StatelessWidget {
  const StreamingText({
    super.key,
    required this.text,
    this.isStreaming = false,
    this.result,
  });

  final String text;
  final bool isStreaming;
  final JudgeResult? result;

  @override
  Widget build(BuildContext context) {
    final displayText = text.trim().isEmpty
        ? (isStreaming ? '正在等待 AI 返回评判…' : '尚未生成评判。')
        : text;
    return Semantics(
      liveRegion: true,
      label: isStreaming ? 'AI 评判正在生成' : 'AI 评判结果',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (result != null) ...<Widget>[
            Align(child: _VerdictChip(verdict: result!.verdict)),
            const SizedBox(height: 8),
          ],
          MarkdownBody(
            data: displayText,
            selectable: true,
            softLineBreak: true,
          ),
          if (isStreaming) ...<Widget>[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

class _VerdictChip extends StatelessWidget {
  const _VerdictChip({required this.verdict});

  final JudgeVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (verdict) {
      JudgeVerdict.correct => (Icons.check_circle_outline, '推断状态：正确'),
      JudgeVerdict.partiallyCorrect => (
          Icons.warning_amber_rounded,
          '推断状态：部分正确',
        ),
      JudgeVerdict.incorrect => (Icons.cancel_outlined, '推断状态：不正确'),
      JudgeVerdict.unknown => (Icons.help_outline, '未从返回文字识别判定状态'),
    };
    return Chip(avatar: Icon(icon, size: 18), label: Text(label));
  }
}
