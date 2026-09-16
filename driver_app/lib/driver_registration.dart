import 'package:shared_preferences/shared_preferences.dart';

/// 온보딩에서 받은 단말 등록 정보(adminUrl/deviceId/traccarServerUrl/busNumber) — 영속화 + 인메모리 캐시.
class DriverRegistration {
  DriverRegistration._();

  static const _kAdminUrl = 'admin_url';
  static const _kDeviceId = 'device_id';
  static const _kBusNumber = 'bus_number';
  static const _kTraccarServerUrl = 'traccar_server_url';

  static String? adminUrl;
  static String? deviceId;
  static String? busNumber;
  static String? traccarServerUrl;

  static bool get isRegistered => deviceId != null;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    adminUrl = prefs.getString(_kAdminUrl);
    deviceId = prefs.getString(_kDeviceId);
    busNumber = prefs.getString(_kBusNumber);
    traccarServerUrl = prefs.getString(_kTraccarServerUrl);
  }

  // ponytail: TEMP 우회 — Rails 서버 주소가 아직 안 정해져서 폰에서 실제 접속 테스트가 어려운 동안,
  // Traccar 실전송 자체를 먼저 검증하기 위해 register API 호출/PIN 검증을 건너뛴다.
  // 서버 확정되면 아래를 ApiClient.register() 호출(이전 구현, api_client.dart에 그대로 있음)로 되돌릴 것.
  static const _tempTraccarServerUrl = 'http://yehyunserver.iptime.org:5055';

  /// adminUrl만 저장하고 deviceId는 결정론적으로 생성(`{host}-1a2b3c`) — 테스트 전에 Traccar
  /// 관리화면(`yehyunserver.iptime.org:8082`)에서 이 값으로 디바이스를 먼저 등록해둬야 한다.
  static Future<void> register({required String url, required String pin}) async {
    final cleanUrl = url.trim().isEmpty ? 'demo.local' : url.trim();
    final host = cleanUrl.replaceAll(RegExp(r'^https?://'), '');

    adminUrl = cleanUrl;
    deviceId = '$host-1a2b3c';
    traccarServerUrl = _tempTraccarServerUrl;
    busNumber = '13'; // ponytail: TEMP 목업 — routes API도 같은 사유로 우회 중, 위 주석 참고

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAdminUrl, adminUrl!);
    await prefs.setString(_kDeviceId, deviceId!);
    await prefs.setString(_kTraccarServerUrl, traccarServerUrl!);
    await prefs.setString(_kBusNumber, busNumber!);
  }

  /// 설정화면의 "PIN으로 재등록" — 저장된 등록 정보를 지우고 온보딩으로 돌려보낸다.
  static Future<void> clear() async {
    adminUrl = null;
    deviceId = null;
    busNumber = null;
    traccarServerUrl = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAdminUrl);
    await prefs.remove(_kDeviceId);
    await prefs.remove(_kBusNumber);
    await prefs.remove(_kTraccarServerUrl);
  }
}
