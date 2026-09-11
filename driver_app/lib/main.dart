import 'package:flutter/material.dart';

import 'l10n/app_strings.dart';
import 'l10n/language_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LanguageSettings.load();
  runApp(const DriverApp());
}

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: LanguageSettings.settingsVersion,
      builder: (context, _, child) => MaterialApp(
        locale: LanguageSettings.locale,
        supportedLocales: const [Locale('ko'), Locale('en')],
        title: AppStrings.appName,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF4F46E5), useMaterial3: true),
        home: const HomeScreen(),
      ),
    );
  }
}

/// 임시 홈 — 실제 스플래시/온보딩/메인 화면은 별도 작업(mvp-spec.md 화면 구성)에서 구현.
/// 여기선 다국어 인프라(자동 감지 + 설정에서 전환)만 시연.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Center(child: Text(AppStrings.trackingIdleState)),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.settingsTitle)),
      body: ListView(
        children: [
          _GroupTitle(AppStrings.displayGroup),
          ListTile(
            title: Text(AppStrings.languageLabel),
            subtitle: Text(_languageValueLabel(LanguageSettings.override)),
            trailing: DropdownButton<AppLanguage?>(
              value: LanguageSettings.override,
              onChanged: (value) => LanguageSettings.setLanguage(value),
              items: [
                DropdownMenuItem(value: null, child: Text(AppStrings.languageSystemOption)),
                DropdownMenuItem(value: AppLanguage.ko, child: Text(AppStrings.languageKoOption)),
                DropdownMenuItem(value: AppLanguage.en, child: Text(AppStrings.languageEnOption)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _languageValueLabel(AppLanguage? override) {
    if (override == null) return AppStrings.languageSystemOption;
    return override == AppLanguage.ko ? AppStrings.languageKoOption : AppStrings.languageEnOption;
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.4),
      ),
    );
  }
}
