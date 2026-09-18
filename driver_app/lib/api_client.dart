import 'dart:convert';

import 'package:http/http.dart' as http;

/// 사용자에게 그대로 보여줄 수 있는 실패 사유(네트워크/서버 응답 없음/PIN 오류/잠금 등).
class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class RegisterResult {
  RegisterResult({required this.traccarServerUrl, required this.deviceId});
  final String traccarServerUrl;
  final String deviceId;
}

class RouteInfo {
  RouteInfo({required this.busNumber, this.nextStopName, this.nextStopEtaMinutes});
  final String busNumber;
  final String? nextStopName;
  final int? nextStopEtaMinutes;
}

/// Rails 백엔드(`Integrations::TraccarController`) 호출.
class ApiClient {
  ApiClient._();

  static const _timeout = Duration(seconds: 10);

  static Uri _uri(String adminUrl, String pathAndQuery) {
    final trimmed = adminUrl.trim();
    final normalized = RegExp(r'^https?://').hasMatch(trimmed) ? trimmed : 'http://$trimmed';
    return Uri.parse('$normalized$pathAndQuery');
  }

  /// PIN → { traccarServerUrl, deviceId }. 서버 무응답/타임아웃/PIN 오류/잠금을 각각 구분해 던진다.
  static Future<RegisterResult> register({required String adminUrl, required String pin}) async {
    final http.Response res;
    try {
      res = await http
          .post(_uri(adminUrl, '/integrations/traccar/register'), body: {'pin': pin})
          .timeout(_timeout);
    } on Exception {
      // 타임아웃(TimeoutException)·연결 실패(SocketException/ClientException) 공통 처리 —
      // 운전자에게 원인 구분은 의미 없고 "다시 시도" 액션만 의미 있음.
      throw ApiException('서버에 연결할 수 없습니다. 서버 주소와 네트워크 연결을 확인해주세요.');
    }

    switch (res.statusCode) {
      case 200:
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return RegisterResult(
          traccarServerUrl: body['traccarServerUrl'] as String,
          deviceId: body['deviceId'] as String,
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

  /// 버스번호 + 다음 정류장. 트래킹 시작을 막을 정도로 중요하지 않아 실패 시 예외 대신 null.
  static Future<RouteInfo?> fetchRouteInfo({required String adminUrl, required String deviceId}) async {
    try {
      final res = await http
          .get(_uri(adminUrl, '/integrations/traccar/routes?deviceId=$deviceId'))
          .timeout(_timeout);
      if (res.statusCode != 200) return null;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final next = body['nextStop'] as Map<String, dynamic>?;
      return RouteInfo(
        busNumber: body['busNumber'] as String? ?? '',
        nextStopName: next?['name'] as String?,
        nextStopEtaMinutes: next?['etaMinutes'] as int?,
      );
    } on Exception {
      return null;
    }
  }
}
