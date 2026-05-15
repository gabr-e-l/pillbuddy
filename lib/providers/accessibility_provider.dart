// lib/providers/accessibility_provider.dart
//
// Manages all patient-side accessibility settings:
//   - Theme mode (light / dark / high-contrast)
//   - Font scale (small / medium / large / extra-large)
//   - Button size scale (normal / large / extra-large)
//   - Auto-adapt from system settings (toggle)
//
// Uses SharedPreferences for persistence and MediaQuery/PlatformDispatcher
// to mirror the device's current mode/font when auto-adapt is enabled.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Enums ────────────────────────────────────────────────────────────────────

enum AppThemeMode { light, dark, highContrast }

enum FontSizeOption { small, medium, large, extraLarge }

enum ButtonSizeOption { normal, large, extraLarge }

// ── Provider ─────────────────────────────────────────────────────────────────

class AccessibilityProvider extends ChangeNotifier {
  // ── Prefs keys ──────────────────────────────────────────────────────────
  static const _kThemeMode       = 'acc_theme_mode';
  static const _kFontSize        = 'acc_font_size';
  static const _kButtonSize      = 'acc_button_size';
  static const _kAutoAdapt       = 'acc_auto_adapt';

  // ── State ────────────────────────────────────────────────────────────────
  AppThemeMode   _themeMode   = AppThemeMode.light;
  FontSizeOption _fontSize    = FontSizeOption.medium;
  ButtonSizeOption _buttonSize = ButtonSizeOption.normal;
  bool           _autoAdapt  = false;

  // ── Getters ──────────────────────────────────────────────────────────────
  AppThemeMode   get themeMode   => _themeMode;
  FontSizeOption get fontSize    => _fontSize;
  ButtonSizeOption get buttonSize => _buttonSize;
  bool           get autoAdapt  => _autoAdapt;

  // ── Derived values used by the app ───────────────────────────────────────

  ThemeMode get flutterThemeMode {
    switch (_themeMode) {
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.light:
      case AppThemeMode.highContrast:
        return ThemeMode.light;
    }
  }

  double get fontScaleFactor {
    switch (_fontSize) {
      case FontSizeOption.small:      return 0.85;
      case FontSizeOption.medium:     return 1.0;
      case FontSizeOption.large:      return 1.2;
      case FontSizeOption.extraLarge: return 1.45;
    }
  }

  /// Multiplier applied to button heights / icon sizes.
  double get buttonScaleFactor {
    switch (_buttonSize) {
      case ButtonSizeOption.normal:     return 1.0;
      case ButtonSizeOption.large:      return 1.25;
      case ButtonSizeOption.extraLarge: return 1.5;
    }
  }

  bool get isHighContrast => _themeMode == AppThemeMode.highContrast;

  // ── Initialisation ───────────────────────────────────────────────────────

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
    // Theme: read platform brightness
    final brightness =
        SchedulerBinding.instance.platformDispatcher.platformBrightness;
    _themeMode =
        brightness == Brightness.dark ? AppThemeMode.dark : AppThemeMode.light;

    // Font: read text scale factor (clamp to our options)
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

    // Button size follows font size when auto-adapt is on
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
    if (_autoAdapt) return; // manual changes blocked when auto-adapt is on
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
      // persist what we just computed so they survive next cold start
      await prefs.setString(_kThemeMode, _themeMode.name);
      await prefs.setString(_kFontSize, _fontSize.name);
      await prefs.setString(_kButtonSize, _buttonSize.name);
    }
  }

  // ── Theme builders ────────────────────────────────────────────────────────

  ThemeData buildLightTheme() {
    if (isHighContrast) return _highContrastTheme();
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1A6BFF),
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      fontFamily: 'Roboto',
    );
  }

  ThemeData buildDarkTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1A6BFF),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      fontFamily: 'Roboto',
    );
  }

  ThemeData _highContrastTheme() {
    return ThemeData(
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF000080),
        onPrimary: Colors.white,
        secondary: Color(0xFF000080),
        onSecondary: Colors.white,
        surface: Colors.white,
        onSurface: Colors.black,
        error: Color(0xFFB00020),
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.white,
      useMaterial3: true,
      fontFamily: 'Roboto',
      cardColor: Colors.white,
      dividerColor: Colors.black,
      iconTheme: const IconThemeData(color: Colors.black),
      textTheme: const TextTheme(
        bodyLarge:  TextStyle(color: Colors.black),
        bodyMedium: TextStyle(color: Colors.black),
      ),
    );
  }
}
