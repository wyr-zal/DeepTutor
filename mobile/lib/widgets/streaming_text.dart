import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/judge_result.dart';
import 'rich_markdown.dart';

class StreamingText extends StatelessWidget {
  const StreamingText({
    super.key,
    required this.text,
    this.isStreaming = false,
    this.result,
    this.emptyStreamingText = '正在等待 AI 返回评判…',
    this.emptyText = '尚未生成评判。',
    this.streamingSemanticsLabel = 'AI 评判正在生成',
    this.completedSemanticsLabel = 'AI 评判结果',
  });

  final String text;
  final bool isStreaming;
  final JudgeResult? result;
  final String emptyStreamingText;
  final String emptyText;
  final String streamingSemanticsLabel;
  final String completedSemanticsLabel;

  @override
  Widget build(BuildContext context) {
    final displayText = text.trim().isEmpty
        ? (isStreaming ? emptyStreamingText : emptyText)
        : text;
    return Semantics(
      liveRegion: true,
      label: isStreaming ? streamingSemanticsLabel : completedSemanticsLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (result != null) ...<Widget>[
            Align(child: _VerdictChip(verdict: result!.verdict)),
            const SizedBox(height: 8),
          ],
          if (displayText.isNotEmpty)
            RichMarkdown(
              displayText,
              selectable: true,
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
    final semantic = AppSemanticColors.of(context);
    final colors = Theme.of(context).colorScheme;
    final (icon, label, bg, fg) = switch (verdict) {
      JudgeVerdict.correct => (
          Icons.check,
          '正确',
          semantic.successBg,
          semantic.successFg,
        ),
      JudgeVerdict.partiallyCorrect => (
          Icons.warning_amber_rounded,
          '部分正确',
          semantic.warningBg,
          semantic.warningFg,
        ),
      JudgeVerdict.incorrect => (
          Icons.close,
          '不正确',
          semantic.dangerBg,
          semantic.dangerFg,
        ),
      JudgeVerdict.unknown => (
          Icons.help_outline,
          '未识别',
          colors.surfaceContainerHighest,
          colors.onSurfaceVariant,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
