// 스모크 테스트: 앱이 뜨고, 시스템 언어 감지에 따라 홈 화면 문구가 표시되는지만 확인.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whereismybusapp/main.dart';
import 'package:whereismybusapp/l10n/app_strings.dart';

void main() {
  testWidgets('홈 화면이 뜨고 AppBar에 앱 이름이 표시된다', (WidgetTester tester) async {
    await tester.pumpWidget(const DriverApp());
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.appName), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('설정 화면 진입 시 언어 선택 항목이 보인다', (WidgetTester tester) async {
    await tester.pumpWidget(const DriverApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.languageLabel), findsOneWidget);
  });
}
