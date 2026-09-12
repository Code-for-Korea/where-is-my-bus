import 'package:flutter/material.dart';

import 'app_colors.dart';

/// AppColors 토큰으로 ThemeData를 만든다 — colorSchemeSeed 대신 써서 accent(#4f46e5)가
/// Material3 톤 매핑을 거치지 않고 목업과 정확히 같은 색으로 나오게 한다.
ThemeData buildAppTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final colorScheme = ColorScheme.fromSeed(seedColor: p.accent, brightness: brightness).copyWith(
    primary: p.accent,
    onPrimary: Colors.white,
    surface: p.frame,
    onSurface: p.ink,
    surfaceContainerHighest: p.panelMuted,
    outline: p.border,
    error: p.warn,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: p.frame,
    dividerColor: p.border,
    appBarTheme: AppBarTheme(
      backgroundColor: p.frame,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.ink),
    ),
    listTileTheme: ListTileThemeData(iconColor: p.inkDim, textColor: p.ink),
  );
}
