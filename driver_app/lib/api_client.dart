import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import 'l10n/app_strings.dart';

/// 사용자에게 그대로 보여줄 수 있는 실패 사유(네트워크/서버 응답 없음/PIN 오류/잠금 등).
class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 서버가 보는 버스 위치: 이전·현재·다음 정류장 이름. 해당하는 정류장이 없으면 null.
/// - 정류장에 정차 중이면 현재가 있고, 막 떠났으면 현재는 null(이동 중)이다.
class TripPosition {
  const TripPosition({this.previous, this.current, this.next});

  factory TripPosition.fromJson(Map<String, dynamic>? json) => TripPosition(
        previous: json?['previous'] as String?,
        current: json?['current'] as String?,
        next: json?['next'] as String?,
      );

  final String? previous;
  final String? current;
  final String? next;
}

/// 서버에 열려 있는 운행. 노선은 관리자가 차량에 배정한 것이다.
class TripInfo {
  const TripInfo({required this.id, required this.routeName, required this.position});

  factory TripInfo.fromJson(Map<String, dynamic> json) => TripInfo(
        id: json['id'] as int,
        routeName: json['routeName'] as String? ?? '',
        position: TripPosition.fromJson(json['position'] as Map<String, dynamic>?),
      );

  final int id;
  final String routeName;
  final TripPosition position;
}

/// 이 차량의 번호, 배정된 노선(없으면 null), 진행 중인 운행(없으면 null).
class BusInfo {
  const BusInfo({required this.busNumber, this.routeName, this.activeTrip});

  factory BusInfo.fromJson(Map<String, dynamic> json) {
    final route = json['route'] as Map<String, dynamic>?;
    final trip = json['activeTrip'] as Map<String, dynamic>?;
    return BusInfo(
      busNumber: json['busNumber'] as String? ?? '',
      routeName: route?['name'] as String?,
      activeTrip: trip == null ? null : TripInfo.fromJson(trip),
    );
  }

  final String busNumber;
  final String? routeName;
  final TripInfo? activeTrip;
}

class RegisterResult {
  RegisterResult({required this.traccarServerUrl, required this.deviceId, required this.busNumber, this.routeName});
  final String traccarServerUrl;
  final String deviceId;
  final String busNumber;
  final String? routeName;
}

/// Rails 백엔드(`Integrations::TraccarController`, `Integrations::TripsController`) 호출.
class ApiClient {
  ApiClient._();

  static const _timeout = Duration(seconds: 10);

  static http.Client _client = http.Client();

  /// 테스트에서 가짜 HTTP 클라이언트(MockClient)로 바꿔 끼운다.
  @visibleForTesting
  static set client(http.Client client) => _client = client;

  static Uri _uri(String adminUrl, String pathAndQuery) {
    final trimmed = adminUrl.trim();
    final normalized = RegExp(r'^https?://').hasMatch(trimmed) ? trimmed : 'http://$trimmed';
    return Uri.parse('$normalized$pathAndQuery');
  }

  /// POST — 타임아웃·연결 실패는 운전자에게 원인 구분이 의미 없고 "다시 시도" 액션만 의미 있어서 한 가지 메시지로 합친다.
  static Future<http.Response> _post(String adminUrl, String path, Map<String, String> body) async {
    try {
      return await _client.post(_uri(adminUrl, path), body: body).timeout(_timeout);
    } on Exception {
      throw ApiException(AppStrings.serverUnreachableError);
    }
  }

  /// PIN → 서버 주소·기기 식별자·차량 번호·배정 노선. 서버 무응답/타임아웃/PIN 오류/잠금을 각각 구분해 던진다.
  static Future<RegisterResult> register({required String adminUrl, required String pin}) async {
    final res = await _post(adminUrl, '/integrations/traccar/register', {'pin': pin});

    switch (res.statusCode) {
      case 200:
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return RegisterResult(
          traccarServerUrl: body['traccarServerUrl'] as String,
          deviceId: body['deviceId'] as String,
          busNumber: body['busNumber'] as String? ?? '',
          routeName: (body['route'] as Map<String, dynamic>?)?['name'] as String?,
        );
      case 401:
        throw ApiException('PIN이 올바르지 않습니다.');
      case 409:
        throw ApiException('이미 다른 기기에서 등록된 PIN입니다. 운영자에게 새 PIN 발급을 요청해주세요.');
      case 429:
        throw ApiException('시도 횟수를 초과했습니다. 잠시 후 다시 시도해주세요.');
      default:
        throw ApiException('등록에 실패했습니다 (${res.statusCode}).');
    }
  }

  /// 차량 번호·배정 노선·진행 중인 운행(이전·현재·다음 정류장 포함). 화면 갱신용이라
  /// 실패(무응답/타임아웃/응답 형식 오류)해도 예외 대신 null — 현재 표시를 유지하고 다음 주기에 다시 시도한다.
  static Future<BusInfo?> fetchBusInfo({required String adminUrl, required String deviceId}) async {
    try {
      final res = await _client
          .get(_uri(adminUrl, '/integrations/traccar/bus?deviceId=${Uri.encodeQueryComponent(deviceId)}'))
          .timeout(_timeout);
      if (res.statusCode != 200) return null;

      return BusInfo.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 운행 시작. 노선은 보내지 않는다 — 서버가 차량에 배정된 노선으로 운행을 만든다. 이미 운행 중이면 그 운행을 돌려준다.
  static Future<TripInfo> startTrip({required String adminUrl, required String deviceId}) async {
    final res = await _post(adminUrl, '/integrations/traccar/trips/start', {'deviceId': deviceId});

    switch (res.statusCode) {
      case 200:
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return TripInfo.fromJson(body['trip'] as Map<String, dynamic>);
      case 422:
        throw ApiException(AppStrings.noRouteAssignedError);
      case 404:
        throw ApiException(AppStrings.unknownDeviceError);
      default:
        throw ApiException(AppStrings.startFailedError(res.statusCode));
    }
  }

  /// 운행 종료. 진행 중인 운행이 없어도 서버가 성공으로 응답한다(멱등).
  static Future<void> endTrip({required String adminUrl, required String deviceId}) async {
    final res = await _post(adminUrl, '/integrations/traccar/trips/end', {'deviceId': deviceId});

    switch (res.statusCode) {
      case 200:
        return;
      case 404:
        throw ApiException(AppStrings.unknownDeviceError);
      default:
        throw ApiException(AppStrings.endFailedError(res.statusCode));
    }
  }
}
