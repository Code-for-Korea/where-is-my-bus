// 메인 화면: 배정 노선, 노선 없음 경고, 서버가 보는 위치(이전·현재·다음 정류장) 표시.
// 스플래시 스피너가 무한 애니메이션이라 pumpAndSettle 대신 명시적 pump(duration)으로 진행시킨다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whereismybusapp/api_client.dart';
import 'package:whereismybusapp/l10n/app_strings.dart';
import 'package:whereismybusapp/main.dart';
import 'package:whereismybusapp/tracking_controller.dart';

const _splashDelay = Duration(seconds: 3, milliseconds: 50);
const _routeTransition = Duration(milliseconds: 350);

Future<void> _openMain(WidgetTester tester, {String? routeName = '1번 노선', http.Response? busResponse}) async {
  SharedPreferences.setMockInitialValues({
    'admin_url': 'localhost:3000',
    'device_id': 'dev1',
    'bus_number': '1',
    'route_name': ?routeName,
  });
  ApiClient.client = MockClient((_) async => busResponse ?? http.Response('', 404)); // 기본: 서버 조회 실패
  await tester.pumpWidget(const DriverApp());
  await tester.pump(_splashDelay);
  await tester.pump(_routeTransition);
}

void main() {
  setUp(TrackingController.resetForTest);
  tearDown(TrackingController.resetForTest);

  testWidgets('배정된 노선 이름을 보여준다', (tester) async {
    await _openMain(tester);

    expect(find.textContaining(AppStrings.routeLabel), findsOneWidget);
    expect(find.textContaining('1번 노선'), findsOneWidget);
    expect(find.text(AppStrings.noRouteBanner), findsNothing);
  });

  testWidgets('배정된 노선이 없으면 경고를 항상 보여준다', (tester) async {
    await _openMain(tester, routeName: null);

    expect(find.text(AppStrings.noRouteBanner), findsOneWidget);
    expect(find.textContaining(AppStrings.routeLabel), findsNothing);
  });

  testWidgets('운행 중에는 이전·현재·다음 정류장을 보여준다', (tester) async {
    await _openMain(tester);

    TrackingController.isTracking.value = true;
    TrackingController.position.value =
        const TripPosition(previous: '고성터미널', current: '고성시장', next: '고성병원');
    await tester.pump();

    expect(find.text(AppStrings.positionTitle), findsOneWidget);
    expect(find.text('고성터미널'), findsOneWidget);
    expect(find.text('고성시장'), findsOneWidget);
    expect(find.text('고성병원'), findsOneWidget);
    expect(find.text(AppStrings.positionPrevious), findsOneWidget);
    expect(find.text(AppStrings.positionCurrent), findsOneWidget);
    expect(find.text(AppStrings.positionNext), findsOneWidget);
  });

  testWidgets('정류장에서 막 출발했으면 현재는 "이동 중"이다', (tester) async {
    await _openMain(tester);

    TrackingController.isTracking.value = true;
    TrackingController.position.value = const TripPosition(previous: '고성시장', next: '고성병원');
    await tester.pump();

    expect(find.text(AppStrings.positionMoving), findsOneWidget);
    expect(find.text('고성시장'), findsOneWidget);
    expect(find.text('고성병원'), findsOneWidget);
  });

  testWidgets('서버가 아직 위치를 알려주지 않았으면 이전·현재·다음 모두 "—"', (tester) async {
    await _openMain(tester);

    TrackingController.isTracking.value = true;
    await tester.pump();

    expect(find.text(AppStrings.positionNone), findsNWidgets(3));
  });

  testWidgets('운행 중이 아니면 위치 패널을 숨긴다', (tester) async {
    await _openMain(tester);

    expect(find.text(AppStrings.positionTitle), findsNothing);
  });

  testWidgets('서버가 노선을 바꿔 알려주면 화면의 노선 이름이 바뀐다', (tester) async {
    final response = http.Response(
      jsonEncode({'busNumber': '2', 'route': {'name': '2번 노선'}, 'activeTrip': null}),
      200,
      headers: {'content-type': 'application/json'},
    );
    await _openMain(tester, busResponse: response);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.textContaining('2번 노선'), findsOneWidget);
    expect(find.textContaining('1번 노선'), findsNothing);
  });
}
