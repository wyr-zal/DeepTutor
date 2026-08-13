import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../app/theme.dart';

/// Rendering density for [RichMarkdown].
enum RichMarkdownVariant {
  /// Full-size body text (chat messages, quiz stems).
  normal,

  /// Smaller, tighter text for thinking cards and inside quiz cards.
  compact,
}

/// Unified markdown renderer built on `gpt_markdown`, adding LaTeX math
/// (`$...$` / `$$...$$`), syntax-highlighted code blocks (`flutter_highlight`),
/// themed inline code, and tap-through links. Mirrors the web app's
/// `RichMarkdownRenderer` visual contract.
class RichMarkdown extends StatelessWidget {
  const RichMarkdown(
    this.data, {
    super.key,
    this.selectable = true,
    this.variant = RichMarkdownVariant.normal,
  });

  final String data;
  final bool selectable;
  final RichMarkdownVariant variant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final compact = variant == RichMarkdownVariant.compact;

    final baseStyle = (compact
            ? theme.textTheme.bodyMedium
            : theme.textTheme.bodyLarge) ??
        const TextStyle();
    final style = baseStyle.copyWith(
      fontSize: compact ? 13 : 16,
      height: compact ? 1.5 : 1.7,
      color: theme.colorScheme.onSurface,
    );

    return GptMarkdown(
      data,
      style: style,
      useDollarSignsForLatex: true,
      onLinkTap: (url, title) {
        // url_launcher not wired yet; links stay inert but never crash.
      },
      codeBuilder: (context, name, code, closed) => _CodeBlock(
        language: name,
        code: code,
        semantic: semantic,
      ),
      highlightBuilder: (context, text, textStyle) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: semantic.inlineCodeBackground,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: textStyle.copyWith(
            fontFamily: 'monospace',
            fontSize: (textStyle.fontSize ?? style.fontSize ?? 14) * 0.9,
          ),
        ),
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({
    required this.language,
    required this.code,
    required this.semantic,
  });

  final String language;
  final String code;
  final AppSemanticColors semantic;

  @override
  Widget build(BuildContext context) {
    // Code blocks always use a dark slate background, so pair with the dark
    // highlight theme for legible syntax colors.
    final highlightTheme = semantic.isDark ? atomOneDarkTheme : githubTheme;
    final lang = language.trim();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: semantic.codeBlockBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (lang.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
              ),
              child: Text(
                lang,
                style: TextStyle(
                  color: semantic.codeBlockForeground.withValues(alpha: 0.8),
                  fontSize: 11,
                  fontFamily: 'monospace',
                  letterSpacing: 0.5,
                ),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: HighlightView(
              code,
              language: lang.isEmpty ? 'plaintext' : lang,
              theme: highlightTheme,
              padding: const EdgeInsets.all(12),
              textStyle: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: semantic.codeBlockForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
