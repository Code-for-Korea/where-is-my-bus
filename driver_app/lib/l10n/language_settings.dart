import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 앱이 지원하는 언어. `system`은 "저장된 값 없음 = 기기 언어 자동 감지"를 의미하며,
/// 지원 목록 밖 언어(ko/en 외)는 en으로 폴백한다.
enum AppLanguage { ko, en }

/// Riverpod/Provider 없이 static 필드 + ValueNotifier로 언어 설정을 전역 관리.
/// 참고: flutter_app_polish_patterns.md §10 (Riverpod 없는 설정 상태관리).
class LanguageSettings {
  LanguageSettings._();

  static const _prefsKey = 'language_override'; // 'ko' | 'en' | 미저장(=시스템)

  /// null이면 시스템 언어를 따름. 명시적으로 고른 값이면 그 값을 고정.
  static AppLanguage? _override;

  /// 위젯 트리 여러 곳에서 리빌드가 필요할 때 구독할 버전 카운터.
  static final settingsVersion = ValueNotifier<int>(0);

  /// 현재 적용 중인 언어(override 있으면 그 값, 없으면 시스템 언어 감지 결과).
  static AppLanguage get current => _override ?? _detectSystemLanguage();

  /// 사용자가 명시적으로 고른 값인지(=시스템 자동감지가 아닌지).
  static AppLanguage? get override => _override;

  static AppLanguage _detectSystemLanguage() {
    final code = PlatformDispatcher.instance.locale.languageCode;
    return code == 'ko' ? AppLanguage.ko : AppLanguage.en;
  }

  /// 앱 시작 시 1회 호출 — 저장된 선택이 있으면 복원, 없으면 시스템 언어 자동 적용 상태로 둔다.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    _override = switch (saved) {
      'ko' => AppLanguage.ko,
      'en' => AppLanguage.en,
      _ => null,
    };
    settingsVersion.value++;
  }

  /// 설정화면에서 언어를 명시적으로 고를 때. `null`을 넘기면 "시스템 기본값"으로 되돌린다.
  static Future<void> setLanguage(AppLanguage? language) async {
    _override = language;
    final prefs = await SharedPreferences.getInstance();
    if (language == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, language.name);
    }
    settingsVersion.value++;
  }

  static Locale get locale => Locale(current.name);
}
