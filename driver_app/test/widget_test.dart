// 스모크 테스트: 스플래시 → (미등록)온보딩 / (등록됨)메인 → 설정 화면 진입까지 확인.
// 스플래시 스피너가 무한 애니메이션이라 pumpAndSettle 대신 명시적 pump(duration)으로 진행시킨다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:whereismybusapp/main.dart';
import 'package:whereismybusapp/l10n/app_strings.dart';

const _splashDelay = Duration(seconds: 3, milliseconds: 50);
const _routeTransition = Duration(milliseconds: 350);

void main() {
  testWidgets('미등록 상태면 스플래시 후 온보딩 화면으로 이동한다', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const DriverApp());
    expect(find.textContaining(AppStrings.appName), findsOneWidget);

    await tester.pump(_splashDelay);
    await tester.pump(_routeTransition);

    expect(find.text(AppStrings.registerButton), findsOneWidget);
  });

  testWidgets('등록된 상태면 메인 화면에서 설정 화면으로 이동한다', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'admin_url': 'busadmin.gimhae.go.kr',
      'device_id': 'gimhae-13-a8f3c2',
      'bus_number': '13',
    });

    await tester.pumpWidget(const DriverApp());
    await tester.pump(_splashDelay);
    await tester.pump(_routeTransition);

    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.languageLabel), findsOneWidget);
  });
}
