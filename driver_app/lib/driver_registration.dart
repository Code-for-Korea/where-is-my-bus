import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// 온보딩에서 받은 단말 등록 정보(adminUrl/deviceId/traccarServerUrl/busNumber/routeName) — 영속화 + 인메모리 캐시.
/// busNumber·routeName은 서버에서 바뀔 수 있어(관리자가 노선을 다시 배정) 서버 조회 결과로 갱신된다.
class DriverRegistration {
  DriverRegistration._();

  static const _kAdminUrl = 'admin_url';
  static const _kDeviceId = 'device_id';
  static const _kBusNumber = 'bus_number';
  static const _kRouteName = 'route_name';
  static const _kTraccarServerUrl = 'traccar_server_url';

  static String? adminUrl;
  static String? deviceId;
  static String? busNumber;
  static String? routeName;
  static String? traccarServerUrl;

  /// busNumber·routeName이 바뀔 때마다 올라가는 번호 — 화면이 이 값을 구독해 다시 그린다.
  static final revision = ValueNotifier<int>(0);

  static bool get isRegistered => deviceId != null;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    adminUrl = prefs.getString(_kAdminUrl);
    deviceId = prefs.getString(_kDeviceId);
    busNumber = prefs.getString(_kBusNumber);
    routeName = prefs.getString(_kRouteName);
    traccarServerUrl = prefs.getString(_kTraccarServerUrl);
  }

  /// adminUrl + PIN으로 `POST /integrations/traccar/register` 호출 — 성공하면 서버가 내려준
  /// 기기 식별자·위치 전송 주소·차량 번호·배정 노선을 저장한다. 실패 시 ApiException을 그대로 던진다.
  static Future<void> register({required String url, required String pin}) async {
    final cleanUrl = url.trim();
    final result = await ApiClient.register(adminUrl: cleanUrl, pin: pin.trim());

    adminUrl = cleanUrl;
    deviceId = result.deviceId;
    traccarServerUrl = result.traccarServerUrl;
    busNumber = result.busNumber;
    routeName = result.routeName;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAdminUrl, adminUrl!);
    await prefs.setString(_kDeviceId, deviceId!);
    await prefs.setString(_kTraccarServerUrl, traccarServerUrl!);
    await prefs.setString(_kBusNumber, busNumber!);
    await _saveRouteName(prefs);
    revision.value++;
  }

  /// 서버 조회 결과로 차량 번호·배정 노선을 갱신한다 (바뀐 경우에만 저장·재그리기).
  static Future<void> applyBusInfo(BusInfo info) async {
    if (info.busNumber == busNumber && info.routeName == routeName) return;

    busNumber = info.busNumber;
    routeName = info.routeName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBusNumber, busNumber!);
    await _saveRouteName(prefs);
    revision.value++;
  }

  /// 설정화면의 "PIN으로 재등록" — 저장된 등록 정보를 지우고 온보딩으로 돌려보낸다.
  static Future<void> clear() async {
    adminUrl = null;
    deviceId = null;
    busNumber = null;
    routeName = null;
    traccarServerUrl = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAdminUrl);
    await prefs.remove(_kDeviceId);
    await prefs.remove(_kBusNumber);
    await prefs.remove(_kRouteName);
    await prefs.remove(_kTraccarServerUrl);
    revision.value++;
  }

  static Future<void> _saveRouteName(SharedPreferences prefs) async {
    final name = routeName;
    if (name == null) {
      await prefs.remove(_kRouteName);
    } else {
      await prefs.setString(_kRouteName, name);
    }
  }
}
