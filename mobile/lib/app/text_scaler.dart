import 'package:flutter/material.dart';

/// Combines the system accessibility text scaler with the user's in-app
/// reading-size preference instead of replacing the system setting.
class AppTextScaler implements TextScaler {
  const AppTextScaler({
    required this.systemScaler,
    required this.multiplier,
  });

  final TextScaler systemScaler;
  final double multiplier;

  @override
  double scale(double fontSize) => systemScaler.scale(fontSize) * multiplier;

  @override
  @Deprecated(
    'Use scale() because system text scaling can be non-linear.',
  )
  double get textScaleFactor => systemScaler.textScaleFactor * multiplier;

  @override
  TextScaler clamp({
    double minScaleFactor = 0,
    double maxScaleFactor = double.infinity,
  }) {
    return AppTextScaler(
      systemScaler: systemScaler.clamp(
        minScaleFactor: minScaleFactor / multiplier,
        maxScaleFactor: maxScaleFactor / multiplier,
      ),
      multiplier: multiplier,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppTextScaler &&
        other.systemScaler == systemScaler &&
        other.multiplier == multiplier;
  }

  @override
  int get hashCode => Object.hash(systemScaler, multiplier);
}
