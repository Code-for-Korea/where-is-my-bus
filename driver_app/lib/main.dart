import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_strings.dart';
import 'l10n/language_settings.dart';
import 'screens/splash_screen.dart';
import 'theme.dart';
import 'theme_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LanguageSettings.load();
  await ThemeSettings.load();
  runApp(const DriverApp());
}

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: LanguageSettings.settingsVersion,
      builder: (context, _, _) => ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeSettings.mode,
        builder: (context, themeMode, _) => MaterialApp(
          locale: LanguageSettings.locale,
          supportedLocales: const [Locale('ko'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          title: AppStrings.appName,
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          themeMode: themeMode,
          // 목업 폰트 크기가 웹(CSS) 기준이라 실기기에서 들고 보면 작게 느껴짐(SM-A516N 테스트 피드백) —
          // 화면 곳곳의 fontSize를 개별로 고치는 대신 전역 배율로 일괄 확대. 운전 중 빠르게 확인하는
          // 운영 화면이라 시스템 글꼴 설정(접근성 확대 등)보다 앱 자체 가독성을 우선해 고정 배율 사용.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.15)),
            child: child!,
          ),
          home: const SplashScreen(),
        ),
      ),
    );
  }
}
