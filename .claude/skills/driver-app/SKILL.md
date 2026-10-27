---
name: driver-app
description: "When working on the driver_app/ (bus driver Flutter app) — always use this skill when creating or modifying any files under driver_app/ (Dart, android/, ios/, pubspec.yaml), when register/bus/trips start·end API contract changes affect driver_app, or when receiving requests related to the driver app or Flutter app. Key points: local verification required due to lack of Flutter CI, temporary settings (needing rollback), server-driven trip state, Traccar Client SDK behavior rules (init/start/stop), Rails API contract."
---

## 이 스킬이 다루는 상황

모노레포의 `driver_app/`은 Rails와 완전히 별도의 Flutter 앱이다. 위치 수집·전송은 직접 구현하지 않고 [`traccar_client_sdk`](https://www.traccar.org/traccar-client-sdk-flutter/)에 위임한다. 앱은 UI(온보딩/운행 시작·종료/상태 표시)와 **운행 시작·종료를 Rails에 알리는 일**을 맡는다. **좌표는 앱이 Traccar로 직접 보내고 Rails는 좌표를 받지 않는다.**

문서 역할: 현재 구현 설명 `driver_app/mvp-spec.md`(2026-10-24에 현행화, 더 이상 freeze 아님), 설정값 근거·서버 계약·이력 `driver_app/ISSUE.md`, 체크리스트 `driver_app/README.md`. 앱 동작을 바꾸면 이 셋을 같이 갱신한다.

## 최우선 함정: 검증 공백

- 루트 CI는 `driver_app/**` 변경을 무시(`paths-ignore`), Kamal Docker 이미지에도 제외(`.dockerignore`), **Flutter CI는 아직 없다**. driver_app 변경에는 어떤 자동 검증도 돌지 않는다.
- **작업 완료 전 로컬에서 직접 검증**: `cd driver_app && flutter analyze && flutter test`. 빌드 확인이 필요하면 `flutter build apk --debug`(Android) 정도. 검증하지 않았으면 "완료"라고 쓰지 않는다.
- Rails 쪽 계약(register/bus/trips)을 바꿨다면 `lib/api_client.dart`와 파싱 정합성을 양쪽 모두 확인한다.
- 권한 팝업 순서, 백그라운드 전송, 실제 GPS 오차 같은 것은 **실기기에서만** 확인된다. 코드 리뷰만으로 통과시키지 않는다. iOS 실기기·백그라운드·배터리는 아직 미검증이다(`ISSUE.md` "미검증").

## 임시 설정 (원복 필요) — 지우거나 "고치지" 않는다

`ISSUE.md` 상단 "임시 설정 (원복 필요)" 섹션. 실배포 주소가 정해질 때까지 유지하는 항목이라 "정상화"로 보이는 수정이 원복 대기 항목을 깨뜨릴 수 있다.

- **Rails** `traccar_server_url`(`app/controllers/integrations/traccar_controller.rb`) — `TRACCAR_SERVER_URL` 환경변수 → credentials → 로컬 기본값 `http://localhost:5055` 순. 실기기로 시험할 때는 PC의 LAN 주소를 환경변수로 넣는다(compose는 `TRACCAR_SERVER_URL`을 그대로 받는다). 배포 주소가 정해지면 환경변수로 넣는다.
- **Android** `driver_app/android/app/src/main/res/xml/network_security_config.xml` — 내부 테스트 서버 도메인만 평문(cleartext) HTTP 허용. 실배포가 https로 확정되면 이 예외 자체를 제거한다.
- **iOS 실기기**: 배포 서버 주소가 http이면 `Info.plist`에 평문 HTTP 예외를 등록해야 한다(`README.md` 체크리스트).

## 서버가 기준이다 (운행 상태)

- **노선은 운전자가 고르지 않는다.** 관리자가 차량에 노선 하나를 배정하고, 앱은 그 노선으로 운행한다. 앱에는 노선 선택 화면이 없고, 노선 미배정이면 경고 배너를 보이고 운행을 시작할 수 없다(`422 no_route_assigned`).
- **시작**: 서버 `trips/start`가 성공해야 SDK `init`(최초 1회)·`start`를 켠다. SDK 시작이 실패하면(위치 권한 거부 등) 서버 운행을 되돌린다.
- **종료**: 서버 `trips/end`가 성공해야 `tracker.stop()`을 한다. 서버 호출이 실패하면 "운행 중" 상태를 유지하고 다시 누르면 재시도한다.
- **자동 재개**: 화면이 열릴 때 서버에 열린 운행이 있는데 앱이 운행 중이 아니면(앱을 껐다 켬) 위치 전송을 자동으로 켠다. 서버 운행이 이미 끝났는데 앱이 운행 중이면 전송을 멈추고 "서버에서 운행이 종료되었습니다"를 안내한다.
- **동기화**: `TrackingController.syncWithServer()`가 화면이 열릴 때·포그라운드 복귀 때·운행 중 10초마다 `GET /integrations/traccar/bus`를 호출해 차량 번호·배정 노선·이전/현재/다음 정류장을 갱신한다. **무응답이어도 위치 전송은 막지 않고** 마지막 표시를 유지한 채 다음 주기에 재시도한다(에러 다이얼로그를 띄우지 않는다).
- 앱 상태를 서버 응답보다 앞세우지 않는다. 운행 시작·종료 UI를 "낙관적 업데이트"로 바꾸지 않는다.
- **ETA는 없다.** 서버는 정류장 방문 기록으로 계산한 이전·현재·다음 정류장 이름만 내려준다(`position`). 앱에서 도착 시간을 계산하지 않는다.

## Rails API 계약 (바꾸려면 양쪽 동시 확인)

| 엔드포인트 | 앱 쪽 처리 |
|---|---|
| `POST /integrations/traccar/register` `{ pin }` | `200 { traccarServerUrl, deviceId, busNumber, licensePlate, route }`. `401` PIN 불일치 / `409` PIN 1회용 소모 / `429` IP당 5회 실패 15분 잠금. `ApiClient.register()`가 각각 사람이 읽을 메시지로 바꿔 `ApiException`으로 던지고 온보딩 화면이 SnackBar로 노출 |
| `GET /integrations/traccar/bus?deviceId=` | `{ busNumber, licensePlate, route, activeTrip }`. `ApiClient.fetchBusInfo()`는 실패 시 `null` |
| `POST /integrations/traccar/trips/start` `{ deviceId }` | `{ trip }`, 이미 운행 중이면 같은 운행(멱등). `422 no_route_assigned` / `404 unknown_device` |
| `POST /integrations/traccar/trips/end` `{ deviceId }` | `{ ended }`, 진행 중 운행이 없어도 `200` |

- PIN은 1회용이다. 재등록(기기 분실·교체)은 어드민 "PIN 재발급"(`Bus#regenerate_pin!`, `pin_registered_at` 초기화) 후 설정화면 "PIN으로 재등록"으로 진행한다.
- 옛 `positions`·`routes` 엔드포인트와 `nextStop`은 폐지됐다. 되살리는 코드를 만들지 않는다.
- `deviceId`(= `traccar_unique_id`)가 운행 시작·종료의 유일한 인증이다. 기기별 토큰은 후속 과제이므로 로그·화면에 노출하지 않는다.

## Traccar Client SDK 동작 규칙 (실기기 검증 기반, 함정 다수)

- **`tracker.init()` 호출 시점**: 스플래시/온보딩이 아니라 **운전자가 최초로 "운행 시작"을 탭하는 순간**(서버 `trips/start` 성공 직후). SDK는 init 시점부터 센서 구독을 시작하므로 미리 부르면 UI와 실제 동작이 어긋난다.
- **지속추적 토글**: 기본값 `true`(설정화면). SDK `Config`에 "포그라운드 전용 전송" 옵션이 없어서 `TrackingController`(`WidgetsBindingObserver`)가 `keepTracking == false && 운행 중`일 때만 백그라운드 진입 → `stop()`, 포그라운드 복귀 → `start()`로 흉내낸다. `true`면 아무것도 개입하지 않는다 — 이 조건 분기를 건드리지 않는다.
- **`stopDetection: false`(고정)**: true면 iOS 모션 권한(`NSMotionUsageDescription`)이 필요해진다. Android는 SDK 네이티브 AAR이 `ACTIVITY_RECOGNITION`을 항상 선언하므로 `tools:node="remove"`로 명시 제거해 둔다 — 풀면 실기기에서 예상 밖 권한 팝업이 뜬다.
- **위치 전송 고정값**: `distanceMeters 15`, `intervalSeconds 10`, `heartbeatIntervalSeconds 30`, `angleDegrees 0`, `accuracy: high`, `buffer: true`, `wakeLock: false`(Android), `preferPlatformProviders: false`, 로컬 잠금 PIN 미도입. 정류장 Geofence가 30m 정사각형이라 위치가 영역 안에 몇 번 찍혀야 이벤트가 생기므로 **이 값을 느슨하게 바꾸지 않는다.** 근거와 시뮬레이터 측정은 `ISSUE.md` "위치 전송 설정 변경"과 `docs/location-sampling-test.md`. 15m/10초는 시작값이며 실기기 측정이 남아 있다.
- `buffer: true`라 통신이 끊기면 위치를 쌓았다가 **원래 시각 그대로** 나중에 보낸다. Traccar는 과거 시각의 위치로 정류장 이벤트를 만들지 않으므로(`docs/future-improvements.md` 18번) 오프라인 구간의 방문은 기록되지 않을 수 있다.
- **Android 권한 팝업 정상 순서**: ① 위치(포그라운드+정확한 위치) → ② 알림(`POST_NOTIFICATIONS`) → ③ 백그라운드 위치(API 30+는 설정 화면 형태 — "항상 허용" 후 **뒤로가기로 직접 복귀**해야 콜백) → ④ 배터리 최적화. 이 4개 외에 추가로 뜨면 이상 신호.
- Windows 빌드 "different roots" 에러는 `android/gradle.properties`의 `kotlin.incremental=false`로 회피한다(E: 프로젝트 vs C: pub-cache 문제).

## 다국어 (record 기반 자체 구현 — 표준 파이프라인 아님)

- `lib/l10n/app_strings.dart`에 `(ko:, en:)` record로 문구 정의, `AppStrings.xxx`로 조회. `language_settings.dart`가 SharedPreferences로 언어를 영속화하고, 저장값이 없으면 시스템 언어를 감지(`ko`→한국어, 그 외→English)한다.
- `intl`/ARB/`flutter gen-l10n`을 새로 도입하지 않는다 — 2개 언어 기준의 의도적 선택. 3개 이상으로 늘 때만 전환을 검토한다. UI 문구를 추가·수정할 때는 **ko/en 두 값을 모두** 채운다.
- ⚠️ 시스템 언어 자동 감지는 **동작 미확인**이다(시뮬레이터에서 일본어로 바꿔도 한국어로 보였다 — 저장된 언어 설정이 우선했을 가능성, `ISSUE.md` "미검증"). 이 로직을 "정상 동작"으로 간주하고 건드리지 않는다.

## 메타

| 항목 | 값 |
|---|---|
| 패키지명 (pubspec) | `whereismybusapp` |
| Android applicationId | `com.tenminutestudio.whereismybusdriver.AOS` |
| iOS bundle ID | `com.tenminutestudio.whereismybusdriver.iOS` |
| 지원 플랫폼 | iOS, Android (windows/ 는 폴더만 있음, 지원 대상 아님) |

## 검증

```bash
cd driver_app
flutter analyze        # 정적 분석 — 최소
flutter test           # test/ 의 유닛·위젯 테스트 (api_client, tracking_controller, main_screen 등)
flutter run            # 실기기/시뮬레이터 — 권한·SDK 동작 확인은 여기서만 가능
```

- 로컬 end-to-end: 저장소 루트에서 `docker compose up -d` 후 iOS 시뮬레이터로 앱을 실행한다(절차는 `driver_app/README.md` "iOS 시뮬레이터로 e2e 확인하기"). 시드 차량의 PIN은 `docker compose exec rails bin/rails db:seed`가 출력하고, 이미 쓴 PIN이면 관리자 화면에서 "PIN 재발급"을 한다.
- 변경 근거(확정 동작·설정값)가 새로 생기면 `driver_app/ISSUE.md`에 한 줄 사유와 함께 기록하는 것이 이 저장소의 관례다.

## 성공 기준

- `flutter analyze`/`flutter test`가 로컬에서 통과한다.
- 임시 설정(원복 필요) 항목을 의도와 다르게 제거·변경하지 않았다.
- 운행 시작·종료가 서버 응답을 기준으로 유지된다(실패 시 상태 불변, 재시도 가능).
- SDK 관련 조건 분기(init 시점, keepTracking, stopDetection/권한 제거)와 위치 전송 고정값이 그대로이거나, 바꿨다면 근거를 `ISSUE.md`에 기록했다.
- ko/en 문구가 둘 다 채워졌다.
- Rails 계약을 건드렸다면 `lib/api_client.dart`와 양쪽 정합성을 확인했다.

## 열린 질문 / 프로젝트마다 다를 수 있는 부분

- 정류장 크라우드소싱 등록 화면은 미구현(SDK 범위 밖, 직접 구현 필요) — 구현 요청 시 `mvp-spec.md`와 `ISSUE.md` "미채택"을 먼저 확인한다.
- 앱스토어/플레이스토어 배포 파이프라인·릴리즈 키스토어는 전부 미구성이다.
- 운전자가 종료를 누르지 못하고 앱이 꺼지면 서버 운행이 열린 채 남는다(자동 종료 미정, `docs/future-improvements.md` 3번). 앱을 다시 켜면 위치 전송이 재개된다.
- Flutter CI 도입 여부는 미결 — 도입되면 "검증 공백" 절을 갱신한다.
