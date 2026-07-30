import 'package:flutter/material.dart';

const _lightScheme = ColorScheme.light(
  primary: Color(0xFF2563EB),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFDBEAFE),
  onPrimaryContainer: Color(0xFF172554),
  secondary: Color(0xFF475569),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFE2E8F0),
  onSecondaryContainer: Color(0xFF1E293B),
  error: Color(0xFFD92D20),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFEE4E2),
  onErrorContainer: Color(0xFF7A271A),
  surface: Color(0xFFFFFFFF),
  onSurface: Color(0xFF0D0D0D),
  surfaceContainerLow: Color(0xFFF7F7F7),
  surfaceContainer: Color(0xFFF2F2F2),
  outline: Color(0xFF737373),
  outlineVariant: Color(0xFFE5E5E5),
);

const _darkScheme = ColorScheme.dark(
  primary: Color(0xFFD4734B),
  onPrimary: Color(0xFF2C1208),
  primaryContainer: Color(0xFF63311F),
  onPrimaryContainer: Color(0xFFFFDBCC),
  secondary: Color(0xFFC7B7AA),
  onSecondary: Color(0xFF2D211B),
  secondaryContainer: Color(0xFF44352E),
  onSecondaryContainer: Color(0xFFEBDDD4),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: Color(0xFF1A1918),
  onSurface: Color(0xFFE8E4DE),
  surfaceContainerLow: Color(0xFF211F1D),
  surfaceContainer: Color(0xFF242220),
  outline: Color(0xFFA9A19B),
  outlineVariant: Color(0xFF3A3634),
);

ThemeData buildDeepTutorTheme(Brightness brightness) {
  final scheme = brightness == Brightness.light ? _lightScheme : _darkScheme;
  final base = ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    useMaterial3: true,
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      centerTitle: true,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
  );
}
