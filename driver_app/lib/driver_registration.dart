import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

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

  /// adminUrl + PIN으로 `POST /integrations/traccar/register` 호출 — 성공하면
  /// { traccarServerUrl, deviceId }를 서버로부터 받아 저장한다. 실패 시 ApiException을 그대로 던진다.
  static Future<void> register({required String url, required String pin}) async {
    final cleanUrl = url.trim();
    final result = await ApiClient.register(adminUrl: cleanUrl, pin: pin.trim());

    adminUrl = cleanUrl;
    deviceId = result.deviceId;
    traccarServerUrl = result.traccarServerUrl;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAdminUrl, adminUrl!);
    await prefs.setString(_kDeviceId, deviceId!);
    await prefs.setString(_kTraccarServerUrl, traccarServerUrl!);
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
