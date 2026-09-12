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
          home: const SplashScreen(),
        ),
      ),
    );
  }
}
