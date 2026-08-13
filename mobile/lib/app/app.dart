import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/font_scale_controller.dart';
import '../features/settings/theme_controller.dart';
import 'routes.dart';
import 'text_scaler.dart';
import 'theme.dart';

class DeepTutorApp extends ConsumerWidget {
  const DeepTutorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeId = ref.watch(themeControllerProvider);
    final fontScale = ref.watch(fontScaleControllerProvider);
    return MaterialApp.router(
      title: 'DeepTutor',
      debugShowCheckedModeBanner: false,
      theme: buildDeepTutorTheme(themeId),
      // Single-theme model: the chosen AppThemeId already carries its own
      // brightness, so we pin themeMode to light and never fall back to a
      // system light/dark pair (Snow and Cream are both light-brightness).
      themeMode: ThemeMode.light,
      routerConfig: router,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: AppTextScaler(
              systemScaler: mediaQuery.textScaler,
              multiplier: fontScale,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
