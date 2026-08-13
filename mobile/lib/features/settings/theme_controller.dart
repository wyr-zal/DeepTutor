import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme.dart';

/// Persists the user's chosen theme locally (independent of the web app's
/// server-side `ui.theme`). Defaults to following the OS brightness on first
/// launch: dark systems get [AppThemeId.dark], light systems get
/// [AppThemeId.snow] — mirroring the web bootstrap heuristic.
final themeControllerProvider =
    NotifierProvider<ThemeController, AppThemeId>(ThemeController.new);

class ThemeController extends Notifier<AppThemeId> {
  static const _prefsKey = 'deeptutor_theme';

  @override
  AppThemeId build() {
    // build() is synchronous; return a sensible default immediately (avoids a
    // first-frame flash) then reconcile with persisted storage asynchronously.
    _load();
    return _systemDefault();
  }

  static AppThemeId _systemDefault() {
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark ? AppThemeId.dark : AppThemeId.snow;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    if (stored == null) return;
    final restored = AppThemeId.fromStorage(stored);
    if (restored != state) state = restored;
  }

  Future<void> setTheme(AppThemeId id) async {
    if (state != id) state = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, id.storageValue);
  }
}
