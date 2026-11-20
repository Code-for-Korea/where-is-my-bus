import 'dart:async';

import 'package:flutter/services.dart';
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
  static const _batteryChannel = MethodChannel('driver_app/battery');
  static const _syncInterval = Duration(seconds: 10); // 운행 중 서버가 보는 위치를 화면에 갱신하는 주기

  static TraccarClientSdk _sdk = TraccarClientSdk();
  // 운전자가 운행 중인 상태(서버에 운행이 열려 있음) — keepTracking이 꺼져 있을 때 앱이 백그라운드로 나가면
  // isTracking(실제 SDK 전송 상태)만 잠시 false가 되고, 이 값은 그대로 유지돼서 포그라운드로 돌아오면 다시 start()한다.
  static bool _onDuty = false;
  // 서버 호출을 포함한 시작/종료 진행 중 — 연타와 경쟁을 막는다.
  static bool _busy = false;
  // 시작/종료가 일어날 때마다 올라간다. 그 전에 출발한 서버 조회 결과가 늦게 도착해 상태를 되돌리는 것을 막는다.
  static int _epoch = 0;
  static bool _lifecycleObserverAttached = false;
  static Timer? _syncTimer;
  // start() 뒤 실제 전송이 켜졌는지 다시 확인하는 간격.
  @visibleForTesting
  static Duration verifyDelay = const Duration(milliseconds: 500);

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
  @visibleForTesting
  static Future<void> onAppLifecycleChanged(AppLifecycleState state) async {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground) {
      // 지속추적이 꺼져 있으면 아래 분기가 start()를 맡는다. 켜져 있으면 OS가 백그라운드에서 전송을 정리했을 수 있어 확인한다.
      // 복구를 먼저 끝낸 뒤 서버 상태를 맞춘다: 서버 운행이 이미 끝났다면 복구로 켠 전송을 곧바로 sync가 끈다.
      if (keepTracking.value) await _recoverIfStopped();
      unawaited(syncWithServer()); // 앱이 꺼져 있는 동안 서버 쪽 운행이 바뀌었을 수 있다
    }

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

    final bool sending;
    try {
      sending = await _startSdk();
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
    // 서버 운행은 열렸는데 위치 전송이 안 켜진 것으로 보이면 운행은 유지하고 운전자에게 알린다 (오판으로 정상 운행을 끊지 않는다).
    if (!sending) lastError.value = AppStrings.locationUnstable;
    unawaited(_requestBatteryExemption());
  }

  /// Android 절전(Doze·제조사 배터리 관리)에 걸리면 한동안 되다가 멈춘다 — 배터리 최적화 예외를 시스템 팝업으로 요청한다.
  /// 이미 예외면 아무것도 안 띄운다. iOS 등 채널이 없는 곳은 조용히 넘어간다(best-effort).
  static Future<void> _requestBatteryExemption() async {
    try {
      await _batteryChannel.invokeMethod<void>('request');
    } on MissingPluginException {
      // Android 외 플랫폼
    } catch (e) {
      debugPrint('TrackingController: battery exemption request failed: $e');
    }
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

  /// 위치 전송을 켠다. 운행을 시작(또는 자동 재개)할 때마다 SDK를 처음 시작할 때와 같은 절차(init → setConfig → start)로 만든다.
  /// init()은 "운행 시작" 탭 이후에만 부른다 — 미리 부르면 버튼 누르기 전부터 GPS 센서가 켜진다.
  ///
  /// 앱을 백그라운드에 둔 채 운행을 끝내고 다시 시작하면, Dart는 "이미 초기화됨"으로 알고 있어도 네이티브 쪽 상태가
  /// 어긋나 start()가 예외 없이 끝나고도 전송이 안 켜질 수 있다. 그래서 Dart 쪽 플래그에 기대지 않고 매번 다시 초기화하고(init은
  /// 멱등), 실제로 전송이 켜졌는지 isTracking()으로 확인한다. 안 켜졌으면 한 번 처음부터 다시 시도한다.
  /// 끝까지 확인되지 않으면 false를 돌려준다(호출한 쪽이 경고를 띄운다). 확인 자체가 불가능한 경우는 켜진 것으로 본다.
  static Future<bool> _startSdk() async {
    final config = Config(
      serverUrl: DriverRegistration.traccarServerUrl!,
      deviceId: DriverRegistration.deviceId!,
      // 정류장 영역(30m 정사각형) 안에 위치가 반드시 몇 번 찍히도록 SDK 기본값보다 촘촘하게 보낸다:
      // 15m 이동 또는 10초마다. mvp-spec.md "위치 추적 고정값" 참고.
      // 화면 잠금·백그라운드에서 CPU가 잠들어 일정 시간 뒤 위치 전송이 멈추는 것을 막는다 (ISSUE.md "백그라운드 전송").
      wakeLock: true,
      location: const LocationConfig(
        accuracy: Accuracy.high,
        distanceMeters: 15,
        intervalSeconds: 10,
        heartbeatIntervalSeconds: 30,
        stopDetection: false, // true면 iOS 모션 권한이 딸려옴
      ),
    );

    await _initSdk(config);
    if (await _querySending() != true) await _sdk.start(); // 이미 전송 중이면(앱 재실행 뒤 서비스가 살아 있는 경우) 다시 켜지 않는다
    if (await _confirmSending()) return true;

    debugPrint('TrackingController: location sending did not start, retrying from scratch');
    await _logDiagnostics();
    try {
      await _sdk.stop();
    } catch (e) {
      debugPrint('TrackingController: stop before retry failed: $e');
    }
    await _initSdk(config);
    await _sdk.start();
    if (await _confirmSending()) return true;

    await _logDiagnostics();
    return false;
  }

  // init()은 SDK에 저장된 설정이 이미 있으면 새 값을 무시한다 — 재등록·서버 변경 뒤에도 옛 주소·기기 ID로
  // 전송하지 않도록 setConfig로 매번 덮어쓴다.
  static Future<void> _initSdk(Config config) async {
    await _sdk.init(config);
    await _sdk.setConfig(config);
  }

  /// 실제 전송 여부. SDK가 답하지 못하면 null.
  static Future<bool?> _querySending() async {
    try {
      return await _sdk.isTracking();
    } catch (e) {
      debugPrint('TrackingController: isTracking failed: $e');
      return null;
    }
  }

  /// start() 직후에는 SDK 상태가 아직 갱신되기 전일 수 있어 잠깐 간격을 두고 몇 번 확인한다. 확인할 수 없으면(null) 켜진 것으로 본다.
  static Future<bool> _confirmSending() async {
    for (var attempt = 0; attempt < 4; attempt++) {
      if (await _querySending() != false) return true;
      if (attempt < 3) await Future<void>.delayed(verifyDelay);
    }
    return false;
  }

  static Future<void> _logDiagnostics() async {
    try {
      final entries = await _sdk.getLogs();
      for (final entry in entries.reversed.take(5).toList().reversed) {
        debugPrint('TrackingController: sdk log: ${entry.message}');
      }
    } catch (e) {
      debugPrint('TrackingController: sdk logs unavailable: $e');
    }
  }

  /// 앞으로 돌아왔을 때 운행 중인데 실제 전송이 꺼져 있으면(OS가 백그라운드에서 정리한 경우 등) 다시 켠다.
  static Future<void> _recoverIfStopped() async {
    if (_busy || !_onDuty) return;
    if (await _querySending() != false) return;
    if (_busy || !_onDuty) return; // 조회하는 동안 운행이 끝났거나 다른 시작/종료가 시작됐다

    debugPrint('TrackingController: sending stopped while on duty, restarting');
    // 복구하는 동안 syncWithServer가 끼어들어 stop한 직후 다시 켜지는 일이 없도록 toggle과 같이 _busy로 막는다.
    _busy = true;
    _epoch++;
    try {
      if (!await _startSdk()) lastError.value = AppStrings.locationUnstable;
    } catch (e) {
      debugPrint('TrackingController: recover failed: $e');
      lastError.value = AppStrings.startFailedPermission; // 조용히 넘어가면 운행 중으로 보이는데 위치가 안 나간다
    } finally {
      _busy = false;
      _epoch++;
    }
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
    final bool sending;
    try {
      sending = await _startSdk();
    } catch (e) {
      debugPrint('TrackingController: resume failed: $e');
      lastError.value = AppStrings.startFailedPermission;
      return;
    }
    _setOnDuty(true);
    if (!sending) lastError.value = AppStrings.locationUnstable;
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
    unawaited(TrackingController.onAppLifecycleChanged(state));
  }
}

class TrackingLogEntry {
  TrackingLogEntry({required this.time, required this.started});
  final DateTime time;
  final bool started;
}
