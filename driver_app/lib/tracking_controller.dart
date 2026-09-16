import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:traccar_client_sdk/traccar_client_sdk.dart';

import 'api_client.dart';
import 'driver_registration.dart';

/// 위치 추적 상태 — `traccar_client_sdk` 연동. serverUrl/deviceId는 온보딩 register API 응답값(DriverRegistration).
class TrackingController {
  TrackingController._();

  static const _kKeepTracking = 'keep_tracking';
  static const _routeRefreshInterval = Duration(seconds: 30); // heartbeatIntervalSeconds와 동일 주기

  static final _sdk = TraccarClientSdk();
  static bool _initialized = false;
  // 운전자가 "운행 시작"을 누르고 아직 "정지"를 누르지 않은 상태 — keepTracking이 꺼져 있을 때
  // 앱이 백그라운드로 나가면 isTracking(실제 SDK 전송 상태)만 잠시 false가 되고, 이 값은 그대로
  // 유지돼서 포그라운드로 돌아오면 자동으로 다시 start()한다.
  static bool _onDuty = false;
  static bool _lifecycleObserverAttached = false;
  static Timer? _routeRefreshTimer;

  static final isTracking = ValueNotifier<bool>(false);
  // 기본 켜짐 — 지속추적이 꺼져 있으면 앱을 나가는 순간 위치 전송 자체가 끊겨 서비스 목적이
  // 무력화된다. 설정화면에서 끄는 건 가능하지만(상시 화면 고정 등 특수 운용), 기본은 안전하게.
  static final keepTracking = ValueNotifier<bool>(true);
  static final logs = ValueNotifier<List<TrackingLogEntry>>(const []);

  // "운행 시작" 실패(권한 거부, SDK 초기화 오류 등) 시 UI(MainScreen)가 SnackBar로 보여줄 메시지.
  static final lastError = ValueNotifier<String?>(null);
  // ponytail: TEMP 목업 초기값 — register API 우회 중이라 routes API도 응답을 못 받는다(driver_registration.dart
  // 상단 주석 참고). 실접속 되면 _refreshRouteInfo가 성공하는 순간 진짜 값으로 덮어쓴다.
  static final nextStopName = ValueNotifier<String?>('고성종합버스터미널');
  static final nextStopEtaMinutes = ValueNotifier<int?>(3);

  static DateTime? lastSentAt;
  static const lastCoord = '35.2285, 128.8894'; // ponytail: 목업 고정 좌표, SDK 좌표 콜백 연동 시 실측값으로 교체

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

  /// 재등록(PIN 초기화) 전 강제 정지 — 운행 중이 아니면 아무 일도 안 한다.
  static Future<void> forceStop() async {
    _routeRefreshTimer?.cancel();
    if (!isTracking.value) return;
    try {
      await _sdk.stop();
    } catch (e) {
      debugPrint('TrackingController: forceStop failed: $e');
    }
    _onDuty = false;
    isTracking.value = false;
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
    lastError.value = null;
    try {
      if (starting) {
        // init()은 최초 "운행 시작" 탭에서 지연 호출 — 미리 부르면 버튼 누르기 전부터 GPS 센서가 켜짐.
        if (!_initialized) {
          await _sdk.init(Config(
            serverUrl: DriverRegistration.traccarServerUrl!,
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
      // GPS 권한 거부 등 SDK 자체 실패 — 상태는 그대로 유지하고 UI(SnackBar)에 사유를 보여준다.
      lastError.value = starting ? '운행 시작에 실패했습니다. 위치 권한을 확인해주세요.' : '운행 정지에 실패했습니다.';
      return;
    }

    _onDuty = starting;
    isTracking.value = starting;
    final now = DateTime.now();
    if (starting) {
      lastSentAt = now;
      _startRouteRefresh();
    } else {
      _routeRefreshTimer?.cancel();
    }
    logs.value = [
      TrackingLogEntry(time: now, started: starting),
      ...logs.value,
    ];
  }

  // "다음 정류장 · N분" 표시용 — Traccar SDK 전송과 별개로 Rails에 직접 물어본다.
  // 실패(서버 무응답 등)해도 트래킹 자체는 막지 않고 조용히 넘어간다 — 다음 주기에 재시도.
  static void _startRouteRefresh() {
    unawaited(_refreshRouteInfo());
    _routeRefreshTimer?.cancel();
    _routeRefreshTimer = Timer.periodic(_routeRefreshInterval, (_) => unawaited(_refreshRouteInfo()));
  }

  static Future<void> _refreshRouteInfo() async {
    final adminUrl = DriverRegistration.adminUrl;
    final deviceId = DriverRegistration.deviceId;
    if (adminUrl == null || deviceId == null) return;

    final info = await ApiClient.fetchRouteInfo(adminUrl: adminUrl, deviceId: deviceId);
    if (info == null) return; // 무응답/타임아웃 — 이전 값 유지, 다음 주기에 재시도
    nextStopName.value = info.nextStopName;
    nextStopEtaMinutes.value = info.nextStopEtaMinutes;
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
