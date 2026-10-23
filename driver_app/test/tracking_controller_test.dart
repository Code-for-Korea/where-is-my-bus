import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:traccar_client_sdk/traccar_client_sdk.dart';
import 'package:whereismybusapp/api_client.dart';
import 'package:whereismybusapp/driver_registration.dart';
import 'package:whereismybusapp/l10n/app_strings.dart';
import 'package:whereismybusapp/tracking_controller.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

const _trip = {
  'id': 7,
  'routeId': 1,
  'routeName': '1번 노선',
  'startedAt': '2026-10-24T09:00:00+09:00',
  'position': {'previous': null, 'current': null, 'next': '고성터미널'},
};

/// 위치 전송 SDK 대역 — 호출 순서를 기록하고, 필요하면 시작 실패(권한 거부)를 흉내낸다.
class _FakeSdk extends TraccarClientSdk {
  final calls = <String>[];
  bool failStart = false;

  @override
  Future<void> init(Config config) async => calls.add('init');

  @override
  Future<void> start() async {
    calls.add('start');
    if (failStart) throw Exception('permission denied');
  }

  @override
  Future<void> stop() async => calls.add('stop');
}

/// 서버 대역 — 경로별 응답을 바꿀 수 있고 요청을 기록한다.
class _Server {
  http.Response Function() start = () => _json({'trip': _trip});
  http.Response Function() end = () => _json({'ended': true});
  Future<http.Response> Function() bus = () async => _json({'busNumber': '1', 'route': {'name': '1번 노선'}, 'activeTrip': null});
  final requests = <String>[];

  int count(String path) => requests.where((r) => r.endsWith(path)).length;

  MockClient get client => MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        switch (request.url.path) {
          case '/integrations/traccar/trips/start':
            return start();
          case '/integrations/traccar/trips/end':
            return end();
          case '/integrations/traccar/bus':
            return bus();
        }
        return http.Response('', 404);
      });
}

void main() {
  late _FakeSdk sdk;
  late _Server server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'admin_url': 'localhost:3000',
      'device_id': 'dev1',
      'traccar_server_url': 'http://localhost:5055',
      'bus_number': '1',
      'route_name': '1번 노선',
    });
    await DriverRegistration.load();
    TrackingController.resetForTest();
    sdk = _FakeSdk();
    server = _Server();
    TrackingController.sdk = sdk;
    ApiClient.client = server.client;
  });

  tearDown(TrackingController.resetForTest);

  group('운행 시작', () {
    test('서버에 운행을 시작한 뒤에야 위치 전송을 켠다', () async {
      await TrackingController.toggle();

      expect(server.requests, ['POST /integrations/traccar/trips/start']);
      expect(sdk.calls, ['init', 'start']);
      expect(TrackingController.isTracking.value, isTrue);
      expect(TrackingController.position.value!.next, '고성터미널');
      expect(TrackingController.lastError.value, isNull);
      expect(TrackingController.logs.value.single.started, isTrue);
    });

    test('노선이 배정되지 않았으면(422) 위치 전송을 켜지 않고 안내한다', () async {
      server.start = () => _json({'error': 'no_route_assigned'}, 422);

      await TrackingController.toggle();

      expect(TrackingController.lastError.value, AppStrings.noRouteAssignedError);
      expect(TrackingController.isTracking.value, isFalse);
      expect(sdk.calls, isEmpty);
    });

    test('서버에 닿지 못하면 위치 전송을 켜지 않는다', () async {
      ApiClient.client = MockClient((_) async => throw const SocketException('down'));

      await TrackingController.toggle();

      expect(TrackingController.lastError.value, AppStrings.serverUnreachableError);
      expect(TrackingController.isTracking.value, isFalse);
      expect(sdk.calls, isEmpty);
    });

    test('위치 권한이 거부되면 서버에 열린 운행을 되돌리고 안내한다', () async {
      sdk.failStart = true;

      await TrackingController.toggle();

      expect(TrackingController.lastError.value, AppStrings.startFailedPermission);
      expect(TrackingController.isTracking.value, isFalse);
      expect(server.count('/trips/start'), 1);
      expect(server.count('/trips/end'), 1);
    });
  });

  group('운행 종료', () {
    setUp(() async {
      await TrackingController.toggle(); // 운행 시작
      server.requests.clear();
      sdk.calls.clear();
    });

    test('서버에 운행을 종료한 뒤에 위치 전송을 멈춘다', () async {
      await TrackingController.toggle();

      expect(server.requests, ['POST /integrations/traccar/trips/end']);
      expect(sdk.calls, ['stop']);
      expect(TrackingController.isTracking.value, isFalse);
      expect(TrackingController.position.value, isNull);
      expect(TrackingController.logs.value.first.started, isFalse);
    });

    test('서버가 종료를 확인하지 못하면 운행 중 상태를 유지하고 다시 누르면 재시도한다', () async {
      server.end = () => http.Response('boom', 503);

      await TrackingController.toggle();

      expect(TrackingController.lastError.value, AppStrings.endFailedError(503));
      expect(TrackingController.isTracking.value, isTrue);
      expect(sdk.calls, isEmpty);

      server.end = () => _json({'ended': true});
      await TrackingController.toggle();

      expect(TrackingController.isTracking.value, isFalse);
      expect(sdk.calls, ['stop']);
    });
  });

  group('서버와 맞추기 (앱을 다시 켰을 때 등)', () {
    test('서버에 열린 운행이 있으면 위치 전송을 자동으로 재개한다', () async {
      server.bus = () async => _json({
            'busNumber': '1',
            'route': {'name': '1번 노선'},
            'activeTrip': {..._trip, 'position': {'previous': '고성터미널', 'current': '고성시장', 'next': '고성병원'}},
          });

      await TrackingController.syncWithServer();

      expect(sdk.calls, ['init', 'start']);
      expect(TrackingController.isTracking.value, isTrue);
      expect(TrackingController.position.value!.current, '고성시장');
      expect(server.count('/trips/start'), 0); // 새 운행을 만들지 않는다
    });

    test('서버 쪽 운행이 이미 끝났으면 위치 전송을 멈추고 알린다', () async {
      await TrackingController.toggle();
      sdk.calls.clear();

      await TrackingController.syncWithServer(); // 기본 응답: 열린 운행 없음

      expect(sdk.calls, ['stop']);
      expect(TrackingController.isTracking.value, isFalse);
      expect(TrackingController.lastError.value, AppStrings.tripEndedByServer);
    });

    test('열린 운행이 없고 운행 중도 아니면 아무 일도 하지 않는다', () async {
      await TrackingController.syncWithServer();

      expect(sdk.calls, isEmpty);
      expect(TrackingController.isTracking.value, isFalse);
      expect(TrackingController.lastError.value, isNull);
    });

    test('서버에 닿지 못하면 현재 상태를 그대로 둔다', () async {
      await TrackingController.toggle();
      sdk.calls.clear();
      ApiClient.client = MockClient((_) async => throw const SocketException('down'));

      await TrackingController.syncWithServer();

      expect(TrackingController.isTracking.value, isTrue);
      expect(sdk.calls, isEmpty);
    });

    test('관리자가 노선을 바꾸면 차량 번호·노선 이름이 갱신된다', () async {
      server.bus = () async => _json({'busNumber': '2', 'route': {'name': '2번 노선'}, 'activeTrip': null});

      await TrackingController.syncWithServer();

      expect(DriverRegistration.busNumber, '2');
      expect(DriverRegistration.routeName, '2번 노선');
    });

    test('노선 배정이 풀리면 노선 이름이 비워진다', () async {
      server.bus = () async => _json({'busNumber': '1', 'route': null, 'activeTrip': null});

      await TrackingController.syncWithServer();

      expect(DriverRegistration.routeName, isNull);
    });

    test('운행을 종료하는 사이 늦게 도착한 옛 조회 결과로 위치 전송을 다시 켜지 않는다', () async {
      await TrackingController.toggle(); // 운행 중
      final gate = Completer<http.Response>();
      server.bus = () => gate.future;

      final sync = TrackingController.syncWithServer(); // 조회가 아직 서버 응답을 기다리는 중
      await Future<void>.delayed(Duration.zero);
      await TrackingController.toggle(); // 그 사이 운전자가 운행 종료
      sdk.calls.clear();

      gate.complete(_json({'busNumber': '1', 'route': {'name': '1번 노선'}, 'activeTrip': _trip})); // 종료 전 상태
      await sync;

      expect(TrackingController.isTracking.value, isFalse);
      expect(sdk.calls, isEmpty);
    });
  });

  group('재등록 전 강제 정지', () {
    test('운행 중이면 서버 운행을 종료해 보고 위치 전송을 멈춘다', () async {
      await TrackingController.toggle();
      server.requests.clear();
      sdk.calls.clear();

      await TrackingController.forceStop();

      expect(server.count('/trips/end'), 1);
      expect(sdk.calls, ['stop']);
      expect(TrackingController.isTracking.value, isFalse);
    });

    test('서버 종료가 실패해도 재등록은 막지 않는다', () async {
      await TrackingController.toggle();
      server.end = () => http.Response('boom', 500);
      sdk.calls.clear();

      await TrackingController.forceStop();

      expect(sdk.calls, ['stop']);
      expect(TrackingController.isTracking.value, isFalse);
    });

    test('운행 중이 아니면 서버를 부르지 않는다', () async {
      await TrackingController.forceStop();

      expect(server.requests, isEmpty);
      expect(sdk.calls, isEmpty);
    });
  });
}
