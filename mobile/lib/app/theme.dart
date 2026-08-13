import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// The three shipped theme families, mirrored from the web app's
/// `globals.css` palettes (Glass intentionally omitted on mobile).
enum AppThemeId {
  snow('默认', Brightness.light),
  cream('奶油', Brightness.light),
  dark('深色', Brightness.dark);

  const AppThemeId(this.label, this.brightness);

  final String label;
  final Brightness brightness;

  static AppThemeId fromStorage(String? raw) {
    return switch (raw) {
      'snow' => AppThemeId.snow,
      'cream' => AppThemeId.cream,
      'dark' => AppThemeId.dark,
      _ => AppThemeId.snow,
    };
  }

  String get storageValue => name;
}

/// Semantic colors that Material's [ColorScheme] cannot express directly,
/// carried on [ThemeData.extensions]. Mirrors the extra web CSS tokens used
/// by thinking cards, code blocks, quiz options, and chat bubbles.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.thinkingCardBackground,
    required this.thinkingCardBorder,
    required this.codeBlockBackground,
    required this.codeBlockForeground,
    required this.inlineCodeBackground,
    required this.quizOptionBackground,
    required this.quizOptionSelectedBorder,
    required this.userBubble,
    required this.assistantBubbleBorder,
    required this.successBg,
    required this.successFg,
    required this.warningBg,
    required this.warningFg,
    required this.dangerBg,
    required this.dangerFg,
    required this.isDark,
  });

  final Color thinkingCardBackground;
  final Color thinkingCardBorder;
  final Color codeBlockBackground;
  final Color codeBlockForeground;
  final Color inlineCodeBackground;
  final Color quizOptionBackground;

  /// Border of a selected-but-unsubmitted quiz option (primary tone).
  final Color quizOptionSelectedBorder;

  final Color userBubble;
  final Color assistantBubbleBorder;

  // Status palette, shared by quiz option states, verdict chips, and
  // difficulty badges. Each has a soft background and a saturated foreground.
  /// Correct / easy / positive.
  final Color successBg;
  final Color successFg;

  /// Partial / medium / caution.
  final Color warningBg;
  final Color warningFg;

  /// Incorrect / hard / error.
  final Color dangerBg;
  final Color dangerFg;

  /// True for dark-family themes; used to pick a code-highlight theme.
  final bool isDark;

  static AppSemanticColors of(BuildContext context) {
    return Theme.of(context).extension<AppSemanticColors>() ??
        _fallback(Theme.of(context).colorScheme);
  }

  static AppSemanticColors _fallback(ColorScheme scheme) {
    return AppSemanticColors(
      thinkingCardBackground: scheme.surfaceContainerLow,
      thinkingCardBorder: scheme.outlineVariant,
      codeBlockBackground: const Color(0xFF1F2937),
      codeBlockForeground: const Color(0xFFE5E7EB),
      inlineCodeBackground: scheme.surfaceContainerHighest,
      quizOptionBackground: scheme.surfaceContainerLow,
      quizOptionSelectedBorder: scheme.primary,
      userBubble: scheme.primaryContainer,
      assistantBubbleBorder: scheme.outlineVariant,
      successBg: const Color(0x2216A34A),
      successFg: const Color(0xFF16A34A),
      warningBg: const Color(0x22D97706),
      warningFg: const Color(0xFFD97706),
      dangerBg: const Color(0x22DC2626),
      dangerFg: const Color(0xFFDC2626),
      isDark: scheme.brightness == Brightness.dark,
    );
  }

  @override
  AppSemanticColors copyWith({
    Color? thinkingCardBackground,
    Color? thinkingCardBorder,
    Color? codeBlockBackground,
    Color? codeBlockForeground,
    Color? inlineCodeBackground,
    Color? quizOptionBackground,
    Color? quizOptionSelectedBorder,
    Color? userBubble,
    Color? assistantBubbleBorder,
    Color? successBg,
    Color? successFg,
    Color? warningBg,
    Color? warningFg,
    Color? dangerBg,
    Color? dangerFg,
    bool? isDark,
  }) {
    return AppSemanticColors(
      thinkingCardBackground:
          thinkingCardBackground ?? this.thinkingCardBackground,
      thinkingCardBorder: thinkingCardBorder ?? this.thinkingCardBorder,
      codeBlockBackground: codeBlockBackground ?? this.codeBlockBackground,
      codeBlockForeground: codeBlockForeground ?? this.codeBlockForeground,
      inlineCodeBackground: inlineCodeBackground ?? this.inlineCodeBackground,
      quizOptionBackground: quizOptionBackground ?? this.quizOptionBackground,
      quizOptionSelectedBorder:
          quizOptionSelectedBorder ?? this.quizOptionSelectedBorder,
      userBubble: userBubble ?? this.userBubble,
      assistantBubbleBorder:
          assistantBubbleBorder ?? this.assistantBubbleBorder,
      successBg: successBg ?? this.successBg,
      successFg: successFg ?? this.successFg,
      warningBg: warningBg ?? this.warningBg,
      warningFg: warningFg ?? this.warningFg,
      dangerBg: dangerBg ?? this.dangerBg,
      dangerFg: dangerFg ?? this.dangerFg,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      thinkingCardBackground: Color.lerp(
          thinkingCardBackground, other.thinkingCardBackground, t)!,
      thinkingCardBorder:
          Color.lerp(thinkingCardBorder, other.thinkingCardBorder, t)!,
      codeBlockBackground:
          Color.lerp(codeBlockBackground, other.codeBlockBackground, t)!,
      codeBlockForeground:
          Color.lerp(codeBlockForeground, other.codeBlockForeground, t)!,
      inlineCodeBackground:
          Color.lerp(inlineCodeBackground, other.inlineCodeBackground, t)!,
      quizOptionBackground:
          Color.lerp(quizOptionBackground, other.quizOptionBackground, t)!,
      quizOptionSelectedBorder: Color.lerp(
          quizOptionSelectedBorder, other.quizOptionSelectedBorder, t)!,
      userBubble: Color.lerp(userBubble, other.userBubble, t)!,
      assistantBubbleBorder:
          Color.lerp(assistantBubbleBorder, other.assistantBubbleBorder, t)!,
      successBg: Color.lerp(successBg, other.successBg, t)!,
      successFg: Color.lerp(successFg, other.successFg, t)!,
      warningBg: Color.lerp(warningBg, other.warningBg, t)!,
      warningFg: Color.lerp(warningFg, other.warningFg, t)!,
      dangerBg: Color.lerp(dangerBg, other.dangerBg, t)!,
      dangerFg: Color.lerp(dangerFg, other.dangerFg, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

// ── Palette definitions, taken verbatim from web/app/globals.css ──────────

class _Palette {
  const _Palette({
    required this.brightness,
    required this.background,
    required this.foreground,
    required this.card,
    required this.cardForeground,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.secondaryForeground,
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.destructive,
    required this.destructiveForeground,
    required this.border,
  });

  final Brightness brightness;
  final Color background;
  final Color foreground;
  final Color card;
  final Color cardForeground;
  final Color primary;
  final Color primaryForeground;
  final Color secondary;
  final Color secondaryForeground;
  final Color muted;
  final Color mutedForeground;
  final Color accent;
  final Color destructive;
  final Color destructiveForeground;
  final Color border;
}

const _snow = _Palette(
  brightness: Brightness.light,
  background: Color(0xFFFFFFFF),
  foreground: Color(0xFF0D0D0D),
  card: Color(0xFFFFFFFF),
  cardForeground: Color(0xFF0D0D0D),
  primary: Color(0xFF2563EB),
  primaryForeground: Color(0xFFFFFFFF),
  secondary: Color(0xFFF7F7F7),
  secondaryForeground: Color(0xFF0D0D0D),
  muted: Color(0xFFF2F2F2),
  mutedForeground: Color(0xFF6E6E6E),
  accent: Color(0xFFECECEC),
  destructive: Color(0xFFD92D20),
  destructiveForeground: Color(0xFFFFFFFF),
  border: Color(0xFFE5E5E5),
);

const _cream = _Palette(
  brightness: Brightness.light,
  background: Color(0xFFFDFCF9),
  foreground: Color(0xFF1C1816),
  card: Color(0xFFFFFFFF),
  cardForeground: Color(0xFF1C1816),
  primary: Color(0xFFB0501E),
  primaryForeground: Color(0xFFFFFFFF),
  secondary: Color(0xFFF5F2EA),
  secondaryForeground: Color(0xFF1C1816),
  muted: Color(0xFFF1EDE2),
  mutedForeground: Color(0xFF6D645A),
  accent: Color(0xFFECE7D8),
  destructive: Color(0xFFC53A2C),
  destructiveForeground: Color(0xFFFFFFFF),
  border: Color(0xFFE6DECC),
);

const _dark = _Palette(
  brightness: Brightness.dark,
  background: Color(0xFF1A1918),
  foreground: Color(0xFFE8E4DE),
  card: Color(0xFF242220),
  cardForeground: Color(0xFFE8E4DE),
  primary: Color(0xFFD4734B),
  primaryForeground: Color(0xFF1A1918),
  secondary: Color(0xFF2A2725),
  secondaryForeground: Color(0xFFE8E4DE),
  muted: Color(0xFF2A2725),
  mutedForeground: Color(0xFF9B9590),
  accent: Color(0xFF302D2A),
  destructive: Color(0xFFD44A3C),
  destructiveForeground: Color(0xFFFFFFFF),
  border: Color(0xFF3A3634),
);

_Palette _paletteFor(AppThemeId id) => switch (id) {
      AppThemeId.snow => _snow,
      AppThemeId.cream => _cream,
      AppThemeId.dark => _dark,
    };

ColorScheme _schemeFor(_Palette p) {
  return ColorScheme(
    brightness: p.brightness,
    primary: p.primary,
    onPrimary: p.primaryForeground,
    primaryContainer: p.accent,
    onPrimaryContainer: p.foreground,
    secondary: p.secondaryForeground,
    onSecondary: p.secondary,
    secondaryContainer: p.secondary,
    onSecondaryContainer: p.secondaryForeground,
    error: p.destructive,
    onError: p.destructiveForeground,
    surface: p.background,
    onSurface: p.foreground,
    surfaceContainerLowest: p.card,
    surfaceContainerLow: p.secondary,
    surfaceContainer: p.muted,
    surfaceContainerHigh: p.muted,
    surfaceContainerHighest: p.accent,
    onSurfaceVariant: p.mutedForeground,
    outline: p.mutedForeground,
    outlineVariant: p.border,
  );
}

AppSemanticColors _semanticFor(_Palette p) {
  final dark = p.brightness == Brightness.dark;
  return AppSemanticColors(
    thinkingCardBackground: p.card,
    thinkingCardBorder: p.border,
    // Code blocks use a consistent dark slate in all themes so syntax colors
    // stay legible; the light themes still get a slightly lighter slate.
    codeBlockBackground:
        dark ? const Color(0xFF16171B) : const Color(0xFF1F2937),
    codeBlockForeground: const Color(0xFFE5E7EB),
    inlineCodeBackground: p.muted,
    quizOptionBackground: p.secondary,
    quizOptionSelectedBorder: p.primary,
    userBubble: p.accent,
    assistantBubbleBorder: p.border,
    // Status colors: brighter, lower-saturation foregrounds on dark themes so
    // they read against the dark surfaces; soft translucent backgrounds tint
    // option cards / chips without overpowering.
    successBg: dark ? const Color(0x3322C55E) : const Color(0x2216A34A),
    successFg: dark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A),
    warningBg: dark ? const Color(0x33F59E0B) : const Color(0x22D97706),
    warningFg: dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
    dangerBg: dark ? const Color(0x33EF4444) : const Color(0x22DC2626),
    dangerFg: dark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
    isDark: dark,
  );
}

GptMarkdownThemeData _markdownThemeFor(_Palette p, TextTheme text) {
  return GptMarkdownThemeData(
    brightness: p.brightness,
    linkColor: p.primary,
    linkHoverColor: p.primary,
    hrLineColor: p.border,
    h1: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
    h2: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    h3: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    h4: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
  );
}

ThemeData buildDeepTutorTheme(AppThemeId id) {
  final palette = _paletteFor(id);
  final scheme = _schemeFor(palette);
  final base = ThemeData(
    brightness: palette.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    useMaterial3: true,
  );

  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[
      _semanticFor(palette),
      _markdownThemeFor(palette, base.textTheme),
    ],
    appBarTheme: AppBarTheme(
      centerTitle: true,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
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
