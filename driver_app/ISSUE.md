# driver_app — 확정 설정값/근거

확정된 항목의 설정값과 한 줄 사유만 담는다. 전체 논의(대안/기각사유/재검토조건)는 비공개 내부 문서로 관리— 필요하면 팀 채널로 요청.

`mvp-spec.md`는 MVP 최초 정의 시점의 기준선(freeze)이라 이후 갱신하지 않는다. 확정/변경되는 내용은 이 파일과 `README.md`에 반영한다.

## 임시 설정 (원복 필요)

Rails 서버 주소가 아직 안 정해져서 폰에서 실접속 테스트가 어려운 동안, Traccar 실전송 자체를 먼저 검증하려고 깔아둔 임시 우회. 서버 주소 확정되면 전부 원복 대상.

- **driver_app** `DriverRegistration.register()`(`lib/driver_registration.dart`) — `ApiClient.register()`(실제 `POST /register` 호출, `lib/api_client.dart`에 그대로 있음) 대신 네트워크 호출 없이 즉시 성공 처리. PIN 검증 안 함, `deviceId`는 `{adminUrl 입력값}-1a2b3c`로 결정론적 생성, `busNumber`는 목업 `'13'` 고정. → 원복: `ApiClient.register()` 호출로 되돌리기.
- **driver_app** `TrackingController.nextStopName`/`nextStopEtaMinutes`(`lib/tracking_controller.dart`) — routes API도 같은 사유로 응답을 못 받으니 메인화면 "다음 정류장" 칩이 계속 비어 보이지 않도록 목업 초기값(`고성종합버스터미널`/`3분`)을 넣어둠. `_refreshRouteInfo`가 언젠가 실제 응답을 받으면 자동으로 덮어써서 원복됨(코드 변경 불필요) — 단, 그 전까지는 실제 다음 정류장이 아니라 항상 이 고정값이 보인다는 점 QC 때 주의.
- **Rails** `traccar_server_url` 로컬 기본값(`app/controllers/integrations/traccar_controller.rb`) — `http://yehyunserver.iptime.org:5055`로 임시 고정(원래는 `credentials[:traccar][:server_url]`/`ENV["TRACCAR_SERVER_URL"]` 우선). → 원복: 실배포 확정되면 credentials/ENV로 실제 값 주입, 이 로컬 기본값은 그대로 둬도 무해.
- **Android** `network_security_config.xml`(`driver_app/android/app/src/main/res/xml/`) — `yehyunserver.iptime.org`만 평문(cleartext) HTTP 허용. Rails adminUrl을 실제 IP/도메인으로 http 접속 테스트하려면 **이 파일에도 해당 도메인 추가해야 함**(안 하면 register API 재활성화해도 연결 자체가 막힘). → 원복: 실배포가 https면 이 예외 자체를 제거.

## 미채택

논의 배경·사유는 비공개 내부 문서 참고. 결과만:

- 버스번호+PIN 자동 서버 감지 → `adminUrl`은 QR(기본)/수동 입력으로 명시적으로 받음(`mvp-spec.md` 온보딩 섹션).
- 푸시(FCM/APNs) → 미도입, 지속추적 토글로 로컬 제어.
- 위치정보 커스텀 동의 팝업 → 미도입, SDK 기본 OS 팝업 사용.

## 보류 (기본값 고정, 노출 안 함)

### 설정 > Advanced settings (buffer/wakelock/stopDetection/preferPlatformProviders/password)

| 항목 | 값 | 사유 |
|---|---|---|
| `buffer` | `true` (고정) | 전송 실패 재시도 큐, 끄는 옵션 자체가 무의미 |
| `wakeLock` (Android) | `false` (고정) | 배터리 소모, '지속추적' 토글로 UX 대체 |
| `stopDetection` | `false` (고정) | 켜면 iOS 모션 권한이 추가로 필요해짐 — 아래 참고 |
| `preferPlatformProviders` (Android) | `false` (고정) | 디버깅/OEM 우회용, 운전자 UI에 불필요 |
| `password`(로컬 잠금 PIN) | 미도입 | 온보딩 PIN 등록 체계와 개념 중복 |

재검토 조건: 배터리·정차 운영 이슈 실제 발생 시 `stopDetection`부터.

### `stopDetection: false`
`stopDetection: true`일 때만 iOS `MotionActivityDetector`가 생성돼 모션 권한(`NSMotionUsageDescription`)이 필요해짐 → 끔, `Info.plist`에 `NSMotionUsageDescription` 불필요.

Android는 다름 — 네이티브 라이브러리(`org.traccar:traccar-client-sdk-android` AAR)가 `stopDetection` 설정값과 무관하게 `ACTIVITY_RECOGNITION`(신체 활동 정보) 권한을 매니페스트에 항상 선언해 실기기에서 동의 팝업이 뜸. `AndroidManifest.xml`에 `tools:node="remove"`로 명시 제거해서 iOS와 동일하게 요청 자체가 안 뜨도록 맞춤.

### interval / angle / heartbeat
UI 비노출, MVP 고정값 사용(`intervalSeconds`/`heartbeatIntervalSeconds` 30초, `angleDegrees` 0). 값 표는 `mvp-spec.md`의 "위치 추적 고정값" 참고. 재검토 조건: 배터리·정확도 이슈 시 `intervalSeconds`부터.

## 확정 동작

### `tracker.init()` 호출 시점
스플래시/온보딩이 아니라 **운전자가 최초로 "운행 시작"을 탭하는 순간** 호출(이후 인스턴스 재사용). SDK가 `init()` 시점부터 센서 구독을 시작하므로, 미리 부르면 "버튼 눌러야 위치가 작동한다"는 UI 인상과 실제 동작이 어긋남.

### 지속추적 문구 — 최선노력, 보장 아님
`AppStrings.keepTrackingSub`를 단정형("계속 전송")에서 최선노력 힌트("앱을 나가도 전송을 이어가요 · 기기가 종료하면 중단될 수 있어요")로 변경. OS 강제종료 시 Android/iOS 둘 다 전송이 끊길 수 있어 보장 문구는 부정확.

### 지속추적 토글 — 설정화면 이동 + 기본값 `true`
메인화면 토글 제거, 설정화면 "위치 추적" 그룹으로 이동. 기본값 `false`→`true` — 꺼지면 서비스 목적이 무력화되는데 비숙련 운전자가 별도로 켜야 한다는 걸 놓칠 수 있는 실패 케이스 제거.

### 지속추적 꺼짐 — 앱 생명주기로 직접 구현
SDK `Config`엔 "포그라운드일 때만 전송"에 대응하는 옵션이 없음(`start()`하면 무조건 백그라운드까지 전송하는 구조). `TrackingController`가 `WidgetsBindingObserver`로 앱 포그라운드/백그라운드 전환을 직접 감지해서, `keepTracking == false`이고 운행 중일 때만 백그라운드 진입 시 `stop()`, 포그라운드 복귀 시 `start()`를 호출해 흉내냄. `keepTracking == true`(기본값)면 이 로직 자체가 개입하지 않고 SDK 기본 백그라운드 동작에 맡김.

### Windows 빌드 — Kotlin incremental 컴파일러 에러
프로젝트(E:)와 pub-cache/Gradle 홈(C:)이 다른 드라이브면 "different roots" 에러로 빌드 실패 → `android/gradle.properties`에 `kotlin.incremental=false`로 회피.

### Android 권한 팝업 순서(정상 동작)
① 위치정보(포그라운드, 정확한 위치 포함) → ② 알림(`POST_NOTIFICATIONS`, 포그라운드 서비스 상주 알림용) → ③ 백그라운드 위치(`ACCESS_BACKGROUND_LOCATION`, API 30+부터 일반 팝업이 아니라 설정 화면 형태 — "항상 허용" 선택 후 뒤로가기로 앱 복귀해야 콜백됨, 자동 복귀 안 됨) → ④ 배터리 최적화 예외. 이 4개 외 추가로 뜨면 이상 신호.

### `POST /integrations/traccar/register` — 계약
- 요청: `{ pin }` (adminUrl은 요청 대상 서버 자체이므로 body에 없음)
- 성공(200): `{ traccarServerUrl, deviceId }` — `deviceId` = 해당 버스의 `traccar_unique_id`
- 실패: `401`(PIN 불일치) / `429`(IP당 5회 실패 시 15분 잠금, `Rails.cache` 기반 — 신규 gem 미도입)
- driver_app: `ApiClient.register()`(`lib/api_client.dart`)가 타임아웃/네트워크 오류/401/429를 각각 사람이 읽을 메시지로 변환해 `ApiException`으로 던짐 → 온보딩 화면이 SnackBar로 노출.

### `GET /integrations/traccar/routes?deviceId=...` — 계약
- 응답: `{ busNumber, routeName, stops: [{name, lat, lng, avgTravelSeconds}], nextStop: {name, etaMinutes} | null }`
- ETA 계산은 기존 시민화면(`StopsController#arrival`)과 동일 로직을 `RouteProgress`(`app/models/route_progress.rb`)로 공유 추출해서 사용 — 두 화면이 다른 숫자를 보여주는 걸 방지.
- Route에 "활성" 개념이 없어 `bus.routes.first`(position순) 사용 — 버스당 노선 1개 가정이 깨지면 재검토 필요.
- driver_app: `TrackingController`가 운행 시작 시 1회 + 30초 주기로 호출해 메인화면 "다음 정류장" 칩 갱신. 무응답/타임아웃이어도 위치 전송 자체(Traccar SDK, Rails 무관)는 막지 않음 — 실패 시 그냥 다음 주기에 재시도.

### `Bus.pin` / `Bus.traccar_unique_id` — 자동 생성 + PIN 재발급
- 둘 다 버스 생성 시 Rails가 자동 채움(`SecureRandom`) — 운영자 수동입력 폐지, 추측 불가능성 보장. `pin`은 6자리 숫자, 전역 유니크 인덱스 추가(`register` API가 PIN만으로 버스를 특정해야 하므로 필수).
- 어드민 차량 상세화면에 "PIN 재발급" 버튼 — 유출 시 즉시 무효화(재발급하면 옛 PIN으로 register 실패). 운전자는 설정화면 "PIN으로 재등록"으로 새 PIN 입력.
- PIN은 어드민 차량 **목록**에서는 안 보이고 **상세화면**에서만 노출(보안 — 여러 대가 한 화면에 노출되는 범위를 줄임).

## 미구현 (구현 필요)

- Admin: 버스별 QR 코드 생성 화면(후순위, 온보딩은 수동입력으로도 동작).
- 정류장 크라우드소싱 등록 화면(SDK 범위 밖, driver_app 별도 구현).
- 앱스토어/플레이스토어 배포 파이프라인(Android 릴리즈 키스토어, iOS 배포 인증서 등 전체 미구성).
- `traccar-integration.md` 로드맵 2단계: 차량 등록 시 Traccar 디바이스 자동 프로비저닝(REST API) — **완전 후순위, 앱 파트 단독 결정 아님, 팀 논의 후 착수**. 현재는 Admin "신규등록 운영자 지침" 페이지(`/admin/guides/bus_registration`)의 수동 절차로 대체.

## 미검증 (실기기 QC 필요)

코드는 있지만 curl/`flutter analyze`·`flutter test` 수준까지만 검증됨 — 실기기/에뮬레이터로 아직 안 돌려봄.

- 온보딩 register 실패 케이스(서버 무응답/타임아웃/PIN 오류/잠금) SnackBar 노출.
- "운행 시작" 시 SDK 실패(위치 권한 거부 등) SnackBar 노출.
- 메인화면 "다음 정류장" 칩 — 실제 GPS 이동에 따라 30초 주기로 갱신되는지.
- 어드민 "PIN 재발급" → 앱 "PIN으로 재등록" → 새 PIN으로 재등록 전체 흐름.

## 완료

- iOS 위치 권한 팝업 로컬라이제이션(`InfoPlist.strings` ko/en) — 시스템 언어를 따름, 앱 내 언어설정과 무관(OS 공통 동작). `NSMotionUsageDescription`은 미도입(`stopDetection: false`).
- Traccar Client SDK 연동(`init`/`start`/`stop`, 상태표시) — 실기기(SM-A516N)로 위치 도달 확인.
- 백엔드 API 5종 구현: `register`/`routes`(위 계약 참고), `Bus.pin`·`traccar_unique_id` 자동생성 + PIN 재발급, Admin "신규등록 운영자 지침" 페이지. driver_app 실연동 코드도 작성 완료했으나 현재 "임시 설정" 우회로 비활성 상태(위 섹션 참고).
- driver_app 설정화면 "PIN으로 재등록" → `TrackingController.forceStop()` + `DriverRegistration.clear()` 연결.
- Admin 차량/시·도/운행지역/노선/정류장 리스트·상세에 최종수정일자 표시.
