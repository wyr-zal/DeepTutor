import 'package:deeptutor_mobile/app/theme.dart';
import 'package:deeptutor_mobile/features/settings/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppThemeId.fromStorage maps stored strings and falls back to snow', () {
    expect(AppThemeId.fromStorage('snow'), AppThemeId.snow);
    expect(AppThemeId.fromStorage('cream'), AppThemeId.cream);
    expect(AppThemeId.fromStorage('dark'), AppThemeId.dark);
    expect(AppThemeId.fromStorage(null), AppThemeId.snow);
    expect(AppThemeId.fromStorage('bogus'), AppThemeId.snow);
  });

  test('setTheme updates state and persists to SharedPreferences', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // First read triggers build(); default is snow on a light test binding.
    expect(container.read(themeControllerProvider), AppThemeId.snow);

    await container
        .read(themeControllerProvider.notifier)
        .setTheme(AppThemeId.cream);

    expect(container.read(themeControllerProvider), AppThemeId.cream);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('deeptutor_theme'), 'cream');
  });

  test('restores the persisted theme on load', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'deeptutor_theme': 'dark',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // build() returns the synchronous default, then _load() reconciles.
    container.read(themeControllerProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(themeControllerProvider), AppThemeId.dark);
  });

  test('buildDeepTutorTheme wires the expected primary per theme', () {
    expect(buildDeepTutorTheme(AppThemeId.snow).colorScheme.primary,
        const Color(0xFF2563EB));
    expect(buildDeepTutorTheme(AppThemeId.cream).colorScheme.primary,
        const Color(0xFFB0501E));
    expect(buildDeepTutorTheme(AppThemeId.dark).colorScheme.primary,
        const Color(0xFFD4734B));
  });
}
