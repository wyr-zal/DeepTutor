import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final fontScaleControllerProvider =
    NotifierProvider<FontScaleController, double>(FontScaleController.new);

/// Stores a reading-size multiplier local to this device.
///
/// The multiplier is later composed with Android/iOS accessibility scaling, so
/// changing it never disables the system text-size preference.
class FontScaleController extends Notifier<double> {
  static const preferenceKey = 'deeptutor_font_scale';
  static const minScale = 0.85;
  static const maxScale = 1.30;
  static const defaultScale = 1.00;

  @override
  double build() {
    _load();
    return defaultScale;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getDouble(preferenceKey);
    if (stored == null) return;

    final restored = normalize(stored);
    if (restored != state) state = restored;
  }

  /// Updates the visible size while the slider is being dragged.
  void preview(double value) {
    final normalized = normalize(value);
    if (normalized != state) state = normalized;
  }

  /// Persists the current choice when the user completes an adjustment.
  Future<void> setFontScale(double value) async {
    final normalized = normalize(value);
    if (normalized != state) state = normalized;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(preferenceKey, normalized);
  }

  static double normalize(double value) {
    return value.clamp(minScale, maxScale).toDouble();
  }

  static String formatPercentage(double value) =>
      '${(normalize(value) * 100).round()}%';
}
