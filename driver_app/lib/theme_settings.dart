import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 라이트/다크/시스템 3단 순환 테마 설정.
/// LanguageSettings와 같은 패턴(static + ValueNotifier, Riverpod 없음) — l10n/language_settings.dart 참고.
class ThemeSettings {
  ThemeSettings._();

  static const _kThemeMode = 'theme_mode'; // 'light' | 'dark' | 미저장(=system)

  static final mode = ValueNotifier<ThemeMode>(ThemeMode.system);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kThemeMode);
    mode.value = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  /// 설정화면의 테마 아이콘 버튼 — 탭할 때마다 시스템→라이트→다크→시스템 순환.
  static Future<void> cycle() async {
    const order = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
    final next = order[(order.indexOf(mode.value) + 1) % order.length];
    mode.value = next;
    final prefs = await SharedPreferences.getInstance();
    if (next == ThemeMode.system) {
      await prefs.remove(_kThemeMode);
    } else {
      await prefs.setString(_kThemeMode, next.name);
    }
  }
}
