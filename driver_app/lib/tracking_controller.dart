import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:traccar_client_sdk/traccar_client_sdk.dart';

import 'api_client.dart';
import 'driver_registration.dart';
import 'l10n/app_strings.dart';

/// 운행(근무) 상태 — 서버의 운행과 `traccar_client_sdk` 위치 전송을 함께 다룬다.
///
/// 서버가 기준이다: 서버 호출이 성공해야 상태를 바꾼다.
/// - 시작: 서버에 운행 시작(노선은 관리자가 차량에 배정한 것) → 성공하면 위치 전송 시작
/// - 종료: 서버에 운행 종료 → 성공하면 위치 전송 정지
/// - 앱을 다시 켜거나 앞으로 돌아오면 서버를 조회해, 열린 운행이 있으면 위치 전송을 자동으로 재개한다.
/// serverUrl/deviceId는 온보딩 register API 응답값(DriverRegistration).
class TrackingController {
  TrackingController._();

  static const _kKeepTracking = 'keep_tracking';
  static const _syncInterval = Duration(seconds: 10); // 운행 중 서버가 보는 위치를 화면에 갱신하는 주기

  static TraccarClientSdk _sdk = TraccarClientSdk();
  static bool _initialized = false;
  // 운전자가 운행 중인 상태(서버에 운행이 열려 있음) — keepTracking이 꺼져 있을 때 앱이 백그라운드로 나가면
  // isTracking(실제 SDK 전송 상태)만 잠시 false가 되고, 이 값은 그대로 유지돼서 포그라운드로 돌아오면 다시 start()한다.
  static bool _onDuty = false;
  // 서버 호출을 포함한 시작/종료 진행 중 — 연타와 경쟁을 막는다.
  static bool _busy = false;
  // 시작/종료가 일어날 때마다 올라간다. 그 전에 출발한 서버 조회 결과가 늦게 도착해 상태를 되돌리는 것을 막는다.
  static int _epoch = 0;
  static bool _lifecycleObserverAttached = false;
  static Timer? _syncTimer;

  static final isTracking = ValueNotifier<bool>(false);
  // 기본 켜짐 — 지속추적이 꺼져 있으면 앱을 나가는 순간 위치 전송 자체가 끊겨 서비스 목적이
  // 무력화된다. 설정화면에서 끄는 건 가능하지만(상시 화면 고정 등 특수 운용), 기본은 안전하게.
  static final keepTracking = ValueNotifier<bool>(true);
  static final logs = ValueNotifier<List<TrackingLogEntry>>(const []);

  // 시작/종료 실패(서버 오류, 노선 미배정, 권한 거부 등) 시 UI(MainScreen)가 SnackBar로 보여줄 메시지.
  static final lastError = ValueNotifier<String?>(null);
  // 서버가 보는 버스 위치(이전·현재·다음 정류장). 운행 중이 아니거나 아직 조회 전이면 null.
  static final position = ValueNotifier<TripPosition?>(null);

  static DateTime? lastSentAt;

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
    final foreground = state == AppLifecycleState.resumed;
    if (foreground) unawaited(syncWithServer()); // 앱이 꺼져 있는 동안 서버 쪽 운행이 바뀌었을 수 있다

    if (keepTracking.value || !_onDuty) return; // 켜짐이면 SDK 기본 동작에 맡김, 운행중 아니면 무관
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

  /// 재등록(PIN 초기화) 전 강제 정지 — 운행 중이면 서버 운행을 종료해 보고(실패해도 재등록은 진행), 위치 전송을 멈춘다.
  static Future<void> forceStop() async {
    _syncTimer?.cancel();
    _epoch++;
    if (_onDuty) {
      final adminUrl = DriverRegistration.adminUrl;
      final deviceId = DriverRegistration.deviceId;
      if (adminUrl != null && deviceId != null) {
        try {
          await ApiClient.endTrip(adminUrl: adminUrl, deviceId: deviceId);
        } on ApiException catch (e) {
          debugPrint('TrackingController: forceStop endTrip failed: ${e.message}');
        }
      }
      try {
        await _sdk.stop();
      } catch (e) {
        debugPrint('TrackingController: forceStop failed: $e');
      }
    }
    _onDuty = false;
    isTracking.value = false;
    position.value = null;
    _initialized = false; // 새 등록 정보(serverUrl/deviceId)로 다시 init해야 한다
  }

  /// 테스트에서 위치 전송 SDK를 가짜로 바꿔 끼운다.
  @visibleForTesting
  static set sdk(TraccarClientSdk sdk) => _sdk = sdk;

  /// 테스트가 서로 영향을 주지 않도록 상태를 처음으로 되돌린다.
  @visibleForTesting
  static void resetForTest() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _onDuty = false;
    _busy = false;
    _epoch = 0;
    _initialized = false;
    isTracking.value = false;
    position.value = null;
    lastError.value = null;
    logs.value = const [];
    lastSentAt = null;
  }

  static Future<void> setKeepTracking(bool value) async {
    keepTracking.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKeepTracking, value);
  }

  /// 버튼 탭 핸들러(동기 VoidCallback) — 실제 시작/정지는 비동기라 내부에서 fire-and-forget.
  static void toggleTracking() {
    unawaited(toggle());
  }

  /// 운행 시작/종료를 전환하고 끝날 때까지 기다린다. 화면은 toggleTracking을 쓰고, 테스트가 이 쪽을 쓴다.
  static Future<void> toggle() async {
    if (_busy) return;
    _busy = true;
    _epoch++;
    lastError.value = null;
    try {
      if (_onDuty) {
        await _stopDuty();
      } else {
        await _startDuty();
      }
    } finally {
      _busy = false;
      _epoch++;
    }
  }

  static Future<void> _startDuty() async {
    final adminUrl = DriverRegistration.adminUrl;
    final deviceId = DriverRegistration.deviceId;
    if (adminUrl == null || deviceId == null) return;

    final TripInfo trip;
    try {
      trip = await ApiClient.startTrip(adminUrl: adminUrl, deviceId: deviceId);
    } on ApiException catch (e) {
      lastError.value = e.message;
      return;
    }

    try {
      await _startSdk();
    } catch (e) {
      debugPrint('TrackingController: start failed: $e');
      // GPS 권한 거부 등 SDK 자체 실패 — 서버에는 운행이 이미 열렸으므로 되돌리고(실패해도 다음 동기화가 서버 상태를 따른다)
      // 상태는 그대로 두고 UI(SnackBar)에 사유를 보여준다.
      lastError.value = AppStrings.startFailedPermission;
      try {
        await ApiClient.endTrip(adminUrl: adminUrl, deviceId: deviceId);
      } on ApiException catch (_) {}
      return;
    }

    position.value = trip.position;
    _setOnDuty(true);
  }

  static Future<void> _stopDuty() async {
    final adminUrl = DriverRegistration.adminUrl;
    final deviceId = DriverRegistration.deviceId;
    if (adminUrl == null || deviceId == null) return;

    try {
      await ApiClient.endTrip(adminUrl: adminUrl, deviceId: deviceId);
    } on ApiException catch (e) {
      lastError.value = e.message; // 서버가 종료를 확인하지 않았으므로 운행 중 상태 그대로 둔다 — 다시 누르면 재시도
      return;
    }

    try {
      await _sdk.stop();
    } catch (e) {
      debugPrint('TrackingController: stop failed: $e');
      lastError.value = AppStrings.stopFailedError; // 서버 운행은 이미 종료됐다 — 서버가 보내는 위치는 무시된다
    }
    _setOnDuty(false);
  }

  /// init()은 최초 "운행 시작" 탭에서 지연 호출 — 미리 부르면 버튼 누르기 전부터 GPS 센서가 켜짐.
  static Future<void> _startSdk() async {
    if (!_initialized) {
      final config = Config(
        serverUrl: DriverRegistration.traccarServerUrl!,
        deviceId: DriverRegistration.deviceId!,
        // 정류장 영역(30m 정사각형) 안에 위치가 반드시 몇 번 찍히도록 SDK 기본값보다 촘촘하게 보낸다:
        // 15m 이동 또는 10초마다. mvp-spec.md "위치 추적 고정값" 참고.
        location: const LocationConfig(
          accuracy: Accuracy.high,
          distanceMeters: 15,
          intervalSeconds: 10,
          heartbeatIntervalSeconds: 30,
          stopDetection: false, // true면 iOS 모션 권한이 딸려옴
        ),
      );
      await _sdk.init(config);
      // init()은 SDK에 저장된 설정이 이미 있으면 새 값을 무시한다 — 재등록·서버 변경 뒤에도 옛 주소·기기 ID로
      // 전송하지 않도록 매번 덮어쓴다.
      await _sdk.setConfig(config);
      _initialized = true;
    }
    await _sdk.start();
  }

  static void _setOnDuty(bool onDuty) {
    _onDuty = onDuty;
    isTracking.value = onDuty;
    final now = DateTime.now();
    if (onDuty) {
      lastSentAt = now;
      _syncTimer?.cancel();
      _syncTimer = Timer.periodic(_syncInterval, (_) => unawaited(syncWithServer()));
    } else {
      _syncTimer?.cancel();
      position.value = null;
    }
    logs.value = [
      TrackingLogEntry(time: now, started: onDuty),
      ...logs.value,
    ];
  }

  /// 서버가 보는 상태를 가져와 화면(차량 번호·배정 노선·이전/현재/다음 정류장)을 갱신하고,
  /// 서버와 앱의 운행 상태가 어긋나 있으면 서버를 따른다:
  /// - 서버에 열린 운행이 있는데 앱이 운행 중이 아니면(앱이 꺼졌다 켜짐) 위치 전송을 재개한다.
  /// - 서버 운행이 이미 끝났는데 앱이 운행 중이면(관리자가 닫음 등) 위치 전송을 멈춘다.
  /// 서버에 닿지 못하면(무응답/타임아웃) 현재 표시를 그대로 유지하고 다음 주기에 다시 시도한다.
  static Future<void> syncWithServer() async {
    final adminUrl = DriverRegistration.adminUrl;
    final deviceId = DriverRegistration.deviceId;
    if (adminUrl == null || deviceId == null || _busy) return;

    final epoch = _epoch;
    final info = await ApiClient.fetchBusInfo(adminUrl: adminUrl, deviceId: deviceId);
    if (info == null || epoch != _epoch || _busy) return;

    await DriverRegistration.applyBusInfo(info);
    if (epoch != _epoch || _busy) return;

    final trip = info.activeTrip;
    if (trip != null) {
      position.value = trip.position;
      if (!_onDuty) await _resume();
    } else if (_onDuty) {
      await _endLocally();
    }
  }

  static Future<void> _resume() async {
    try {
      await _startSdk();
    } catch (e) {
      debugPrint('TrackingController: resume failed: $e');
      lastError.value = AppStrings.startFailedPermission;
      return;
    }
    _setOnDuty(true);
  }

  static Future<void> _endLocally() async {
    try {
      await _sdk.stop();
    } catch (e) {
      debugPrint('TrackingController: stop (server ended) failed: $e');
    }
    _setOnDuty(false);
    lastError.value = AppStrings.tripEndedByServer;
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
