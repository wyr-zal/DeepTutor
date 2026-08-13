import 'package:deeptutor_mobile/app/text_scaler.dart';
import 'package:deeptutor_mobile/features/settings/font_scale_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('setFontScale persists the selected multiplier', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(fontScaleControllerProvider),
      FontScaleController.defaultScale,
    );

    await container
        .read(fontScaleControllerProvider.notifier)
        .setFontScale(1.15);

    expect(container.read(fontScaleControllerProvider), 1.15);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble(FontScaleController.preferenceKey), 1.15);
  });

  test('restores and clamps a persisted multiplier', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      FontScaleController.preferenceKey: 1.60,
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(fontScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(fontScaleControllerProvider),
        FontScaleController.maxScale);
  });

  test('AppTextScaler preserves system scaling and applies app multiplier', () {
    const scaler = AppTextScaler(
      systemScaler: TextScaler.linear(1.20),
      multiplier: 1.15,
    );

    expect(scaler.scale(20), closeTo(27.6, 0.001));
  });
}
