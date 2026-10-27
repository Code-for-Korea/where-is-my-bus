import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whereismybusapp/api_client.dart';
import 'package:whereismybusapp/l10n/app_strings.dart';

const _adminUrl = 'localhost:3000';
const _deviceId = 'dev1';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// 요청을 기록하면서 정해진 응답을 돌려주는 가짜 서버.
class _FakeServer {
  _FakeServer(this.respond);
  final http.Response Function(http.Request request) respond;
  final requests = <http.Request>[];

  MockClient get client => MockClient((request) async {
        requests.add(request);
        return respond(request);
      });
}

void main() {
  const busJson = {
    'busNumber': '1',
    'licensePlate': '경남70가1001',
    'route': {'id': 1, 'name': '1번 노선', 'stops': []},
    'activeTrip': {
      'id': 7,
      'routeId': 1,
      'routeName': '1번 노선',
      'startedAt': '2026-10-24T09:00:00+09:00',
      'position': {'previous': '고성터미널', 'current': '고성시장', 'next': '고성병원'},
    },
  };

  group('register', () {
    test('차량 번호와 배정 노선을 함께 받는다', () async {
      final server = _FakeServer((_) => _json({
            'traccarServerUrl': 'http://localhost:5055',
            'deviceId': 'abc123',
            'busNumber': '1',
            'licensePlate': '경남70가1001',
            'route': {'id': 1, 'name': '1번 노선', 'stops': []},
          }));
      ApiClient.client = server.client;

      final result = await ApiClient.register(adminUrl: _adminUrl, pin: '123456');

      expect(result.deviceId, 'abc123');
      expect(result.busNumber, '1');
      expect(result.routeName, '1번 노선');
      expect(server.requests.single.url.toString(), 'http://localhost:3000/integrations/traccar/register');
      expect(server.requests.single.bodyFields, {'pin': '123456'});
    });

    test('노선이 배정되지 않은 차량은 routeName이 null이다', () async {
      ApiClient.client = _FakeServer((_) => _json({
            'traccarServerUrl': 'http://localhost:5055',
            'deviceId': 'abc123',
            'busNumber': '1',
            'route': null,
          })).client;

      final result = await ApiClient.register(adminUrl: _adminUrl, pin: '123456');

      expect(result.routeName, isNull);
    });

    for (final entry in {401: 'PIN이 올바르지 않습니다.', 409: '이미 다른 기기에서', 429: '시도 횟수를 초과'}.entries) {
      test('${entry.key} 응답은 사람이 읽을 메시지로 바뀐다', () async {
        ApiClient.client = _FakeServer((_) => _json({'error': 'x'}, entry.key)).client;

        expect(
          () => ApiClient.register(adminUrl: _adminUrl, pin: '000000'),
          throwsA(isA<ApiException>().having((e) => e.message, 'message', contains(entry.value))),
        );
      });
    }

    test('서버에 닿지 못하면 연결 안내 메시지', () async {
      ApiClient.client = MockClient((_) async => throw const SocketException('refused'));

      expect(
        () => ApiClient.register(adminUrl: _adminUrl, pin: '123456'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', AppStrings.serverUnreachableError)),
      );
    });
  });

  group('fetchBusInfo', () {
    test('배정 노선과 진행 중인 운행의 이전·현재·다음 정류장을 읽는다', () async {
      final server = _FakeServer((_) => _json(busJson));
      ApiClient.client = server.client;

      final info = await ApiClient.fetchBusInfo(adminUrl: _adminUrl, deviceId: _deviceId);

      expect(info!.busNumber, '1');
      expect(info.routeName, '1번 노선');
      expect(info.activeTrip!.id, 7);
      expect(info.activeTrip!.position.previous, '고성터미널');
      expect(info.activeTrip!.position.current, '고성시장');
      expect(info.activeTrip!.position.next, '고성병원');
      expect(server.requests.single.url.toString(), 'http://localhost:3000/integrations/traccar/bus?deviceId=dev1');
    });

    test('운행이 없고 노선도 없으면 둘 다 null', () async {
      ApiClient.client = _FakeServer((_) => _json({'busNumber': '2', 'route': null, 'activeTrip': null})).client;

      final info = await ApiClient.fetchBusInfo(adminUrl: _adminUrl, deviceId: _deviceId);

      expect(info!.routeName, isNull);
      expect(info.activeTrip, isNull);
    });

    test('정류장 이동 중이면 현재 정류장이 null이다', () async {
      ApiClient.client = _FakeServer((_) => _json({
            'busNumber': '1',
            'route': {'name': '1번 노선'},
            'activeTrip': {
              'id': 7,
              'routeName': '1번 노선',
              'position': {'previous': '고성시장', 'current': null, 'next': '고성병원'},
            },
          })).client;

      final info = await ApiClient.fetchBusInfo(adminUrl: _adminUrl, deviceId: _deviceId);

      expect(info!.activeTrip!.position.current, isNull);
      expect(info.activeTrip!.position.next, '고성병원');
    });

    test('실패(404·네트워크·형식 오류)는 예외 대신 null', () async {
      ApiClient.client = _FakeServer((_) => _json({'error': 'unknown_device'}, 404)).client;
      expect(await ApiClient.fetchBusInfo(adminUrl: _adminUrl, deviceId: _deviceId), isNull);

      ApiClient.client = MockClient((_) async => throw const SocketException('down'));
      expect(await ApiClient.fetchBusInfo(adminUrl: _adminUrl, deviceId: _deviceId), isNull);

      ApiClient.client = MockClient((_) async => http.Response('<html>', 200));
      expect(await ApiClient.fetchBusInfo(adminUrl: _adminUrl, deviceId: _deviceId), isNull);
    });
  });

  group('startTrip', () {
    test('노선을 보내지 않고 deviceId만 보낸다', () async {
      final server = _FakeServer((_) => _json({'trip': busJson['activeTrip']}));
      ApiClient.client = server.client;

      final trip = await ApiClient.startTrip(adminUrl: _adminUrl, deviceId: _deviceId);

      expect(trip.id, 7);
      expect(trip.routeName, '1번 노선');
      expect(server.requests.single.url.path, '/integrations/traccar/trips/start');
      expect(server.requests.single.bodyFields, {'deviceId': 'dev1'});
    });

    test('422는 "배정된 노선이 없다"는 안내', () async {
      ApiClient.client = _FakeServer((_) => _json({'error': 'no_route_assigned'}, 422)).client;

      expect(
        () => ApiClient.startTrip(adminUrl: _adminUrl, deviceId: _deviceId),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', AppStrings.noRouteAssignedError)),
      );
    });

    test('404는 "서버가 이 기기를 모른다"는 안내', () async {
      ApiClient.client = _FakeServer((_) => _json({'error': 'unknown_device'}, 404)).client;

      expect(
        () => ApiClient.startTrip(adminUrl: _adminUrl, deviceId: _deviceId),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', AppStrings.unknownDeviceError)),
      );
    });

    test('그 밖의 오류와 네트워크 실패', () async {
      ApiClient.client = _FakeServer((_) => http.Response('boom', 500)).client;
      expect(
        () => ApiClient.startTrip(adminUrl: _adminUrl, deviceId: _deviceId),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', AppStrings.startFailedError(500))),
      );

      ApiClient.client = MockClient((_) async => throw const SocketException('down'));
      expect(
        () => ApiClient.startTrip(adminUrl: _adminUrl, deviceId: _deviceId),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', AppStrings.serverUnreachableError)),
      );
    });
  });

  group('endTrip', () {
    test('성공하면 아무것도 돌려주지 않는다', () async {
      final server = _FakeServer((_) => _json({'ended': true}));
      ApiClient.client = server.client;

      await ApiClient.endTrip(adminUrl: _adminUrl, deviceId: _deviceId);

      expect(server.requests.single.url.path, '/integrations/traccar/trips/end');
    });

    test('진행 중인 운행이 없어도 서버가 200이면 성공(멱등)', () async {
      ApiClient.client = _FakeServer((_) => _json({'ended': false})).client;

      await ApiClient.endTrip(adminUrl: _adminUrl, deviceId: _deviceId);
    });

    test('서버 오류와 네트워크 실패는 예외', () async {
      ApiClient.client = _FakeServer((_) => http.Response('boom', 503)).client;
      expect(
        () => ApiClient.endTrip(adminUrl: _adminUrl, deviceId: _deviceId),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', AppStrings.endFailedError(503))),
      );

      ApiClient.client = MockClient((_) async => throw const SocketException('down'));
      expect(
        () => ApiClient.endTrip(adminUrl: _adminUrl, deviceId: _deviceId),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', AppStrings.serverUnreachableError)),
      );
    });
  });
}
