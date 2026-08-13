import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../widgets/rich_markdown.dart';

/// Collapsible card surfacing a reasoning model's `<think>` scratchpad, mirrors
/// the web app's `ModelThinkingCard`.
///
/// Behaviour:
///  - Default-open while the model is still writing (`closed == false`), with a
///    spinner in the header, so the user can watch reasoning live.
///  - Auto-collapses the moment thinking closes.
///  - Once the user toggles it manually, their preference wins for the rest of
///    the message lifetime.
class ThinkingCard extends StatefulWidget {
  const ThinkingCard({
    super.key,
    required this.content,
    required this.closed,
  });

  final String content;
  final bool closed;

  @override
  State<ThinkingCard> createState() => _ThinkingCardState();
}

class _ThinkingCardState extends State<ThinkingCard> {
  bool? _userToggled;

  bool get _open => _userToggled ?? !widget.closed;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final colors = Theme.of(context).colorScheme;
    final hasBody = widget.content.trim().isNotEmpty;
    // Respect the platform "reduce motion" setting: drop the decorative
    // rotate/cross-fade animations (the streaming spinner stays — it conveys
    // state, not decoration).
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final animDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 180);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: semantic.thinkingCardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: semantic.thinkingCardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _userToggled = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: <Widget>[
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: animDuration,
                    child: Icon(
                      Icons.expand_more,
                      size: 16,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.psychology_outlined,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.closed ? '已深度思考' : '正在思考…',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.onSurfaceVariant,
                      letterSpacing: 0.3,
                    ),
                  ),
                  if (!widget.closed) ...<Widget>[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: semantic.thinkingCardBorder),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: hasBody
                  ? RichMarkdown(
                      widget.content,
                      variant: RichMarkdownVariant.compact,
                    )
                  : Text(
                      '正在思考…',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
            ),
            crossFadeState:
                _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: animDuration,
          ),
        ],
      ),
    );
  }
}
