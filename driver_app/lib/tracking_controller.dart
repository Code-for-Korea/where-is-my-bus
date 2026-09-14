import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:traccar_client_sdk/traccar_client_sdk.dart';

import 'driver_registration.dart';

/// 위치 추적 상태 — `traccar_client_sdk` 연동.
/// serverUrl은 register API(`POST /integrations/traccar/register`, 아직 미구현)가 내려줄 값인데
/// 그 전이라 테스트용 고정값을 쓴다. API 붙으면 DriverRegistration에 traccarServerUrl 필드를
/// 추가해 응답값으로 교체. 좌표/다음 정류장은 그때까지 목업 고정값.
class TrackingController {
  TrackingController._();

  static const _kKeepTracking = 'keep_tracking';
  // ponytail: register API 없어 테스트용 고정값. API 붙으면 DriverRegistration의 응답값으로 교체.
  static const _testServerUrl = 'http://yehyunserver.iptime.org:5055';

  static final _sdk = TraccarClientSdk();
  static bool _initialized = false;
  // 운전자가 "운행 시작"을 누르고 아직 "정지"를 누르지 않은 상태 — keepTracking이 꺼져 있을 때
  // 앱이 백그라운드로 나가면 isTracking(실제 SDK 전송 상태)만 잠시 false가 되고, 이 값은 그대로
  // 유지돼서 포그라운드로 돌아오면 자동으로 다시 start()한다.
  static bool _onDuty = false;
  static bool _lifecycleObserverAttached = false;

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
    if (!_lifecycleObserverAttached) {
      _lifecycleObserverAttached = true;
      WidgetsBinding.instance.addObserver(_LifecycleObserver());
    }
  }

  /// mvp-spec "지속추적" 정의: 꺼짐 = 앱이 포그라운드일 때만 전송. SDK 자체엔 이 옵션이 없어서
  /// (start()하면 무조건 백그라운드까지 전송) 앱 생명주기를 직접 감지해 정지/재시작으로 흉내낸다.
  static Future<void> _onAppLifecycleChanged(AppLifecycleState state) async {
    if (keepTracking.value || !_onDuty) return; // 켜짐이면 SDK 기본 동작에 맡김, 운행중 아니면 무관
    final foreground = state == AppLifecycleState.resumed;
    try {
      if (!foreground && isTracking.value) {
        await _sdk.stop();
        isTracking.value = false;
      } else if (foreground && !isTracking.value) {
        await _sdk.start();
        isTracking.value = true;
      }
    } catch (e) {
      debugPrint('TrackingController: lifecycle ${foreground ? 'start' : 'stop'} failed: $e');
    }
  }

  static Future<void> setKeepTracking(bool value) async {
    keepTracking.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKeepTracking, value);
  }

  /// 버튼 탭 핸들러(동기 VoidCallback) — 실제 시작/정지는 비동기라 내부에서 fire-and-forget.
  static void toggleTracking() {
    unawaited(_toggle());
  }

  static Future<void> _toggle() async {
    final starting = !isTracking.value;
    try {
      if (starting) {
        // init()은 최초 "운행 시작" 탭에서 지연 호출 — 미리 부르면 버튼 누르기 전부터 GPS 센서가 켜짐.
        if (!_initialized) {
          await _sdk.init(Config(
            serverUrl: _testServerUrl,
            deviceId: DriverRegistration.deviceId!,
            // mvp-spec.md "위치 추적 고정값" — SDK 기본값 대신 5초 폴링/버스 주행 특성에 맞춘 값.
            location: const LocationConfig(
              accuracy: Accuracy.high,
              distanceMeters: 30,
              intervalSeconds: 30,
              heartbeatIntervalSeconds: 30,
              stopDetection: false, // true면 iOS 모션 권한이 딸려옴
            ),
          ));
          _initialized = true;
        }
        await _sdk.start();
      } else {
        await _sdk.stop();
      }
    } catch (e) {
      debugPrint('TrackingController: ${starting ? 'start' : 'stop'} failed: $e');
      return; // 권한 거부 등 실패 시 상태 그대로 유지 — UI에 반영 안 함
    }

    _onDuty = starting;
    isTracking.value = starting;
    final now = DateTime.now();
    if (starting) lastSentAt = now;
    logs.value = [
      TrackingLogEntry(time: now, started: starting),
      ...logs.value,
    ];
  }
}

class _LifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(TrackingController._onAppLifecycleChanged(state));
  }
}

class TrackingLogEntry {
  TrackingLogEntry({required this.time, required this.started});
  final DateTime time;
  final bool started;
}
