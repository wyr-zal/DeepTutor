import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import 'font_scale_controller.dart';
import 'theme_controller.dart';

/// Bottom sheet that allows the user to switch between the three shipped themes
/// (Snow, Cream, Dark). Each theme shows a color preview (background, card,
/// primary) plus its localized label and a checkmark for the active choice.
Future<void> showThemePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => const _ThemePickerSheet(),
  );
}

class _ThemePickerSheet extends ConsumerWidget {
  const _ThemePickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentId = ref.watch(themeControllerProvider);
    final controller = ref.read(themeControllerProvider.notifier);
    final fontScale = ref.watch(fontScaleControllerProvider);
    final fontScaleController = ref.read(fontScaleControllerProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '外观',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '字体大小',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  FontScaleController.formatPercentage(fontScale),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: fontScale == FontScaleController.defaultScale
                      ? null
                      : () => fontScaleController
                          .setFontScale(FontScaleController.defaultScale),
                  child: const Text('恢复默认'),
                ),
              ],
            ),
            Slider(
              key: const Key('font-scale-slider'),
              value: fontScale,
              min: FontScaleController.minScale,
              max: FontScaleController.maxScale,
              divisions: 9,
              label: FontScaleController.formatPercentage(fontScale),
              semanticFormatterCallback: FontScaleController.formatPercentage,
              onChanged: fontScaleController.preview,
              onChangeEnd: fontScaleController.setFontScale,
            ),
            Text(
              '预览：阅读聊天内容和题目时，文字会立即调整。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            for (final id in AppThemeId.values)
              _ThemeOption(
                id: id,
                selected: id == currentId,
                onTap: () {
                  controller.setTheme(id);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.id,
    required this.selected,
    required this.onTap,
  });

  final AppThemeId id;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Build a miniature theme just to extract its palette for the preview dots.
    final theme = buildDeepTutorTheme(id);
    final scheme = theme.colorScheme;
    final cardColor =
        theme.extension<AppSemanticColors>()?.thinkingCardBackground ??
            scheme.surfaceContainerLowest;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        child: Row(
          children: [
            // Color preview: three dots showing background, card, primary
            _ColorDot(scheme.surface),
            const SizedBox(width: 6),
            _ColorDot(cardColor),
            const SizedBox(width: 6),
            _ColorDot(scheme.primary),
            const SizedBox(width: 16),
            // Label
            Expanded(
              child: Text(
                id.label,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            // Checkmark
            if (selected)
              Icon(
                Icons.check,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1,
        ),
      ),
    );
  }
}
