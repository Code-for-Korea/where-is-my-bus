import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 위치 추적 상태 — `traccar_client_sdk` 연동 전 로컬 스텁(README 제작 체크리스트 미완 항목).
/// SDK를 붙이면 toggleTracking()에서 tracker.start()/stop() 호출로, keepTracking은
/// Config의 백그라운드 옵션 전달로 교체한다. 좌표/다음 정류장은 그때까지 목업 고정값.
class TrackingController {
  TrackingController._();

  static const _kKeepTracking = 'keep_tracking';

  static final isTracking = ValueNotifier<bool>(false);
  // 기본 켜짐 — 지속추적이 꺼져 있으면 앱을 나가는 순간 위치 전송 자체가 끊겨 서비스 목적이
  // 무력화된다. 설정화면에서 끄는 건 가능하지만(상시 화면 고정 등 특수 운용), 기본은 안전하게.
  static final keepTracking = ValueNotifier<bool>(true);
  static final logs = ValueNotifier<List<TrackingLogEntry>>(const []);

  static DateTime? lastSentAt;
  static const lastCoord = '35.2285, 128.8894'; // ponytail: 목업 고정 좌표, SDK 연동 시 실측값으로 교체
  static const nextStopName = '고성종합버스터미널';
  static const nextStopEtaMinutes = 3;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    keepTracking.value = prefs.getBool(_kKeepTracking) ?? true;
  }

  static Future<void> setKeepTracking(bool value) async {
    keepTracking.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKeepTracking, value);
  }

  static void toggleTracking() {
    isTracking.value = !isTracking.value;
    final now = DateTime.now();
    if (isTracking.value) lastSentAt = now;
    logs.value = [
      TrackingLogEntry(time: now, started: isTracking.value),
      ...logs.value,
    ];
  }
}

class TrackingLogEntry {
  TrackingLogEntry({required this.time, required this.started});
  final DateTime time;
  final bool started;
}
