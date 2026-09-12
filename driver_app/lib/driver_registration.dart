import 'package:shared_preferences/shared_preferences.dart';

/// 온보딩에서 받은 단말 등록 정보(adminUrl/deviceId/busNumber).
///
/// `POST /integrations/traccar/register` 서버 엔드포인트가 아직 없다(driver_app/docs/issue.md
/// #미구현 참고) — register()는 그 자리에 들어갈 더미: 입력값 검증 없이 항상 성공 처리하고
/// 목업과 같은 형태의 deviceId를 만들어낸다. 서버 붙으면 이 메서드 본문만
/// HTTP 호출 + 응답 파싱(+ 실패 케이스)으로 교체하면 된다.
class DriverRegistration {
  DriverRegistration._();

  static const _kAdminUrl = 'admin_url';
  static const _kDeviceId = 'device_id';
  static const _kBusNumber = 'bus_number';

  static String? adminUrl;
  static String? deviceId;
  static String? busNumber;

  static bool get isRegistered => deviceId != null;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    adminUrl = prefs.getString(_kAdminUrl);
    deviceId = prefs.getString(_kDeviceId);
    busNumber = prefs.getString(_kBusNumber);
  }

  /// 서버 API가 없어 실패 케이스가 없다 — 항상 성공. 빈 입력이면 자리표시용 값으로 채운다.
  static Future<void> register({required String url, required String pin}) async {
    final cleanUrl = url.trim().isEmpty ? 'demo.local' : url.trim();
    final host = cleanUrl.replaceAll(RegExp(r'^https?://'), '');
    adminUrl = cleanUrl;
    busNumber = '13'; // ponytail: 서버 응답 전까지 목업 고정값, register API 붙으면 응답값으로 교체
    deviceId = '$host-13-a8f3c2';

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAdminUrl, adminUrl!);
    await prefs.setString(_kDeviceId, deviceId!);
    await prefs.setString(_kBusNumber, busNumber!);
  }

  /// 설정화면의 "PIN으로 재등록" — 저장된 등록 정보를 지우고 온보딩으로 돌려보낸다.
  static Future<void> clear() async {
    adminUrl = null;
    deviceId = null;
    busNumber = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAdminUrl);
    await prefs.remove(_kDeviceId);
    await prefs.remove(_kBusNumber);
  }
}
