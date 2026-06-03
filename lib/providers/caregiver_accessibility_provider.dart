// lib/providers/caregiver_accessibility_provider.dart
//
// Manages all caregiver-side accessibility settings independently from the
// patient side.  Uses a separate set of SharedPreferences keys so that each
// role's display preferences are preserved on the same device.
//
// Settings:
//   - Theme mode  : light / dark / high-contrast
//   - Font scale  : small / medium / large / extra-large
//   - Button size : normal / large / extra-large
//   - Auto-adapt  : mirror the device's current mode / font
//
// Colour identity: caregiver accent = 0xFF2BC8A7 (teal).
//
// IMPORTANT – double-scaling guard
// ---------------------------------
// Screens that use this provider should wrap their Scaffold in:
//
//   Theme(data: acc.theme, child: MediaQuery(data: mq.copyWith(textScaler:
//       TextScaler.linear(acc.fontScaleFactor)), child: ...))
//
// Inside those screens, DO NOT manually multiply text sizes by fontScaleFactor
// again – the MediaQuery textScaler already handles it.  Only multiply button
// heights / paddings by buttonScaleFactor where needed.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'accessibility_provider.dart'
    show AppThemeMode, FontSizeOption, ButtonSizeOption;

import 'accessibility_provider.dart'
    show AppThemeMode, FontSizeOption, ButtonSizeOption;

class CaregiverAccessibilityProvider extends ChangeNotifier {
  // ── Prefs keys (caregiver-namespaced) ─────────────────────────────────────
  static const _kThemeMode  = 'cg_acc_theme_mode';
  static const _kFontSize   = 'cg_acc_font_size';
  static const _kButtonSize = 'cg_acc_button_size';
  static const _kAutoAdapt  = 'cg_acc_auto_adapt';

  // ── State ─────────────────────────────────────────────────────────────────
  AppThemeMode     _themeMode   = AppThemeMode.light;
  FontSizeOption   _fontSize    = FontSizeOption.medium;
  ButtonSizeOption _buttonSize  = ButtonSizeOption.normal;
  bool             _autoAdapt   = false;

  // ── Getters ───────────────────────────────────────────────────────────────
  AppThemeMode     get themeMode   => _themeMode;
  FontSizeOption   get fontSize    => _fontSize;
  ButtonSizeOption get buttonSize  => _buttonSize;
  bool             get autoAdapt   => _autoAdapt;

  // ── Derived values ────────────────────────────────────────────────────────

  ThemeMode get flutterThemeMode {
    switch (_themeMode) {
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.light:
      case AppThemeMode.highContrast:
        return ThemeMode.light;
    }
  }

  /// Text scale factor applied via MediaQuery.textScaler.
  /// Screens must NOT also multiply individual font sizes by this value.
  double get fontScaleFactor {
    switch (_fontSize) {
      case FontSizeOption.small:      return 0.90;
      case FontSizeOption.medium:     return 1.0;
      case FontSizeOption.large:      return 1.15;
      case FontSizeOption.extraLarge: return 1.30;
    }
  }

  /// Multiplier for button heights and vertical paddings only.
  double get buttonScaleFactor {
    switch (_buttonSize) {
      case ButtonSizeOption.normal:     return 1.0;
      case ButtonSizeOption.large:      return 1.20;
      case ButtonSizeOption.extraLarge: return 1.40;
    }
  }

  bool get isHighContrast => _themeMode == AppThemeMode.highContrast;
  bool get isDark         => _themeMode == AppThemeMode.dark;

  /// Convenience: returns the correct ThemeData for the current mode.
  ThemeData get theme => isDark ? buildDarkTheme() : buildLightTheme();

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    _autoAdapt = prefs.getBool(_kAutoAdapt) ?? false;

    if (_autoAdapt) {
      _applySystemSettings();
    } else {
      final tm = prefs.getString(_kThemeMode);
      _themeMode = AppThemeMode.values.firstWhere(
        (e) => e.name == tm,
        orElse: () => AppThemeMode.light,
      );

      final fs = prefs.getString(_kFontSize);
      _fontSize = FontSizeOption.values.firstWhere(
        (e) => e.name == fs,
        orElse: () => FontSizeOption.medium,
      );

      final bs = prefs.getString(_kButtonSize);
      _buttonSize = ButtonSizeOption.values.firstWhere(
        (e) => e.name == bs,
        orElse: () => ButtonSizeOption.normal,
      );
    }

    notifyListeners();
  }

  // ── System-settings mirror ────────────────────────────────────────────────

  void _applySystemSettings() {
    final brightness =
        SchedulerBinding.instance.platformDispatcher.platformBrightness;
    _themeMode =
        brightness == Brightness.dark ? AppThemeMode.dark : AppThemeMode.light;

    final systemScale =
        SchedulerBinding.instance.platformDispatcher.textScaleFactor;
    if (systemScale <= 0.9) {
      _fontSize = FontSizeOption.small;
    } else if (systemScale <= 1.1) {
      _fontSize = FontSizeOption.medium;
    } else if (systemScale <= 1.3) {
      _fontSize = FontSizeOption.large;
    } else {
      _fontSize = FontSizeOption.extraLarge;
    }

    switch (_fontSize) {
      case FontSizeOption.small:
      case FontSizeOption.medium:
        _buttonSize = ButtonSizeOption.normal;
        break;
      case FontSizeOption.large:
        _buttonSize = ButtonSizeOption.large;
        break;
      case FontSizeOption.extraLarge:
        _buttonSize = ButtonSizeOption.extraLarge;
        break;
    }
  }

  // ── Setters ───────────────────────────────────────────────────────────────

  Future<void> setThemeMode(AppThemeMode mode) async {
    if (_autoAdapt) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, mode.name);
  }

  Future<void> setFontSize(FontSizeOption size) async {
    if (_autoAdapt) return;
    _fontSize = size;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFontSize, size.name);
  }

  Future<void> setButtonSize(ButtonSizeOption size) async {
    if (_autoAdapt) return;
    _buttonSize = size;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kButtonSize, size.name);
  }

  Future<void> setAutoAdapt(bool value) async {
    _autoAdapt = value;
    if (value) _applySystemSettings();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoAdapt, value);
    if (value) {
      await prefs.setString(_kThemeMode, _themeMode.name);
      await prefs.setString(_kFontSize, _fontSize.name);
      await prefs.setString(_kButtonSize, _buttonSize.name);
    }
  }

  // ── Theme builders (caregiver teal accent) ────────────────────────────────

  static const Color kCaregiverAccent = Color(0xFF2BC8A7);

  ThemeData buildLightTheme() {
    if (isHighContrast) return _highContrastTheme();
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: kCaregiverAccent,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: const Color(0xFFF4F7FF),
      cardColor: Colors.white,
    );
  }

  ThemeData buildDarkTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: kCaregiverAccent,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: const Color(0xFF121212),
      cardColor: const Color(0xFF1E1E2E),
    );
  }

  ThemeData _highContrastTheme() {
    return ThemeData(
      colorScheme: const ColorScheme.light(
        primary:     Color(0xFF007A63),
        onPrimary:   Colors.white,
        secondary:   Color(0xFF007A63),
        onSecondary: Colors.white,
        surface:     Colors.white,
        onSurface:   Colors.black,
        error:       Color(0xFFB00020),
        onError:     Colors.white,
      ),
      scaffoldBackgroundColor: Colors.white,
      cardColor: Colors.white,
      useMaterial3: true,
      fontFamily: 'Roboto',
      dividerColor: Colors.black,
      iconTheme: const IconThemeData(color: Colors.black),
      textTheme: const TextTheme(
        bodyLarge:  TextStyle(color: Colors.black),
        bodyMedium: TextStyle(color: Colors.black),
      ),
    );
  }
}