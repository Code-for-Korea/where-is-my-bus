# driver_app — 확정 설정값/근거

확정된 항목의 설정값과 한 줄 사유만 담는다. 전체 논의(대안/기각사유/재검토조건)는 비공개 내부 문서로 관리— 필요하면 팀 채널로 요청.

`mvp-spec.md`는 한동안 기준선(freeze)이었으나 2026-10-24에 현행화했다(서버 재작성으로 앱 동작이 달라짐). 지금은 현재 구현을 설명하는 문서이며, 설정값의 근거와 계약은 이 파일에, 체크리스트는 `README.md`에 둔다.

## 임시 설정 (원복 필요)

Rails 서버 주소가 확정되면서 register API 우회는 원복 완료(아래 "완료" 참고). 남은 항목은 실배포
주소가 정해지기 전까지 유지되는 로컬/테스트 전용 설정.

- **Rails** `traccar_server_url` 로컬 기본값(`app/controllers/integrations/traccar_controller.rb`) — 환경변수 `TRACCAR_SERVER_URL` → credentials → 로컬 기본값 `http://localhost:5055` 순. 실기기로 시험할 때는 PC의 LAN 주소로 지정하고, 배포 주소가 정해지면 환경변수로 넣는다.
- **Android** `network_security_config.xml`(`driver_app/android/app/src/main/res/xml/`) — 위와 같은 내부 테스트 서버 도메인만 평문(cleartext) HTTP 허용. → 원복: 실배포가 https면 이 예외 자체를 제거.

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
UI 비노출, MVP 고정값 사용(`distanceMeters` 15, `intervalSeconds` 10, `heartbeatIntervalSeconds` 30, `angleDegrees` 0). 현재 값과 이유는 이 문서의 "위치 전송 설정 변경" 참고(`mvp-spec.md`의 표도 같은 값). 재검토 조건: 배터리·정확도 이슈 시 `intervalSeconds`부터.

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
- 성공(200): `{ traccarServerUrl, deviceId, busNumber, licensePlate, route }` — `deviceId` = 해당 버스의 `traccar_unique_id`, `route` = **관리자가 이 차량에 배정한 노선**(`{ id, name, stops }`, 배정 전이면 `null`). 앱은 `busNumber`와 노선 이름을 저장해 메인 화면에 보여준다.
- 실패: `401`(PIN 불일치) / `409`(PIN 1회용 — 이미 다른 기기가 같은 PIN으로 등록 완료, 유출 대응) / `429`(IP당 5회 실패 시 15분 잠금, `Rails.cache` 기반 — 신규 gem 미도입)
- PIN은 최초 등록 성공 시 `bus.pin_registered_at`을 찍어 소모 처리(원자적 조건부 UPDATE로 동시 요청 경쟁 상태 방지). 기기분실/교체 등 정상 재등록은 어드민 "PIN 재발급"(`Bus#regenerate_pin!`)이 `pin_registered_at`도 함께 초기화해서 새 PIN으로 다시 등록 가능하게 한다.
- driver_app: `ApiClient.register()`(`lib/api_client.dart`)가 타임아웃/네트워크 오류/401/409/429를 각각 사람이 읽을 메시지로 변환해 `ApiException`으로 던짐 → 온보딩 화면이 SnackBar로 노출.

### `GET /integrations/traccar/bus?deviceId=...` — 계약 (옛 `routes`를 대체)
- 응답: `{ busNumber, licensePlate, route, activeTrip }` — `route`는 배정된 노선(없으면 `null`), `activeTrip`은 진행 중인 운행 `{ id, routeId, routeName, startedAt, position: { previous, current, next } }`(없으면 `null`). `position`은 서버가 정류장 방문 기록(Geofence 진입/이탈)으로 계산한 **이전·현재·다음 정류장 이름**이다: 정차 중이면 현재가 있고, 막 떠났으면 현재는 `null`(앱은 "이동 중"), 아직 방문 기록이 없으면 다음 = 첫 정류장.
- ETA(몇 분 뒤 도착)는 없다. 옛 `nextStop`은 사라졌다.
- driver_app: `TrackingController.syncWithServer()`가 화면이 열릴 때·앱이 포그라운드로 돌아올 때·운행 중 10초마다 호출해 차량 번호·배정 노선·이전/현재/다음 정류장을 갱신한다. 무응답/타임아웃이면 현재 표시를 유지하고 다음 주기에 재시도(위치 전송 자체는 Traccar SDK라 Rails와 무관).
- 서버에 열린 운행이 있는데 앱이 운행 중이 아니면(앱이 꺼졌다 켜짐) **위치 전송을 자동으로 재개**하고, 서버 운행이 이미 끝났는데 앱이 운행 중이면 위치 전송을 멈추고 "서버에서 운행이 종료되었습니다"를 안내한다.

### `POST /integrations/traccar/trips/start`, `.../trips/end` — 계약
- 요청: `{ deviceId }` (**노선은 보내지 않는다** — 서버가 차량에 배정된 노선으로 운행한다).
- start 성공(200): `{ trip: { id, routeId, routeName, startedAt, position } }`. 이미 운행 중이면 같은 운행을 돌려준다(멱등). `422 { error: "no_route_assigned" }`(배정된 노선 없음 → 앱: "배정된 노선이 없어 운행을 시작할 수 없습니다"), `404 { error: "unknown_device" }`.
- end 성공(200): `{ ended: true|false }` — 진행 중인 운행이 없어도 200(멱등).
- driver_app 규칙: **서버가 기준**이다. 시작은 서버 `trips/start`가 성공해야 위치 전송(SDK `init`/`start`)을 켜고, 종료는 서버 `trips/end`가 성공해야 위치 전송을 멈춘다. 서버 호출이 실패하면 상태를 바꾸지 않고 SnackBar로 안내한다(종료 실패 시 운행 중 상태를 유지하고 다시 누르면 재시도). 서버 운행은 열렸는데 위치 권한 거부 등으로 SDK 시작이 실패하면 서버 운행을 되돌린다.
- 운행 시작·종료는 Traccar를 호출하지 않는다. 기기를 노선의 Traccar 그룹에 넣는 일은 관리자가 차량에 노선을 배정할 때 끝난다.

### `Bus.pin` / `Bus.traccar_unique_id` — 자동 생성 + PIN 재발급
- 둘 다 버스 생성 시 Rails가 자동 채움(`SecureRandom`) — 운영자 수동입력 폐지, 추측 불가능성 보장. `pin`은 6자리 숫자, 전역 유니크 인덱스 추가(`register` API가 PIN만으로 버스를 특정해야 하므로 필수).
- 어드민 차량 상세화면에 "PIN 재발급" 버튼 — 유출 시 즉시 무효화(재발급하면 옛 PIN으로 register 실패). 운전자는 설정화면 "PIN으로 재등록"으로 새 PIN 입력.
- PIN은 어드민 차량 **목록**에서는 안 보이고 **상세화면**에서만 노출(보안 — 여러 대가 한 화면에 노출되는 범위를 줄임).

## 위치 전송 설정 변경 (2026-10-24)

정류장 도착/출발을 "가장 가까운 정류장 계산"이 아니라 **Traccar 정류장 영역(30m 정사각형) 진입/이탈**로 판정하게 되어(`docs/design-event-driven-rewrite.md`), 위치가 영역 안에 반드시 몇 번 찍히도록 전송을 촘촘하게 바꿨다.

| 필드 | 이전 | 변경 | 이유 |
|---|---|---|---|
| `distanceMeters` | 30 | **15** | SDK는 `distanceMeters > 0`이면 거리 기준으로 위치를 보낸다. 30m 간격이면 30m 폭 영역을 지나갈 때 샘플이 1개 안팎이라 경계·도로 위치에 따라 놓칠 수 있다. 15m면 통과당 2~4개 |
| `intervalSeconds` | 30 | **10** | 느리게 움직이거나 정차 중에도 10초 안에 최신 위치가 간다 |
| 그대로 | | `accuracy: high`, `heartbeatIntervalSeconds: 30`, `stopDetection: false` | |

- 15m / 10초는 **시작값**이다. 시뮬레이터에서는 72km/h까지 정류장 4곳 통과 10회가 모두 기록되었다([`docs/location-sampling-test.md`](../docs/location-sampling-test.md)). 실기기에서 같은 방식으로 측정해 조정한다(미검증).
- `buffer`는 SDK 기본값(true)이다 — 통신이 끊기면 위치를 큐에 쌓았다가 **원래 시각 그대로** 나중에 보낸다. Traccar는 과거 시각의 위치로는 정류장 이벤트를 만들지 않으므로(`docs/future-improvements.md` 18번) 오프라인 구간의 정류장 방문은 기록되지 않을 수 있다. 큐는 SQLite에 저장돼 앱·OS를 다시 시작해도 남고, 실패 시 5초~5분 지수 백오프로 재시도한다(SDK 공식 문서). **서버를 껐다 켜는 운영에서는** 꺼지기 전 마지막 위치보다 새로운 위치가 몰려 와 옛 시각 이벤트가 생길 수 있다(`docs/traccar-accessory.md`).

## 미구현 (구현 필요)

- Admin: 버스별 QR 코드 생성 화면(후순위, 온보딩은 수동입력으로도 동작).
- 정류장 크라우드소싱 등록 화면(SDK 범위 밖, driver_app 별도 구현).
- 앱스토어/플레이스토어 배포 파이프라인(Android 릴리즈 키스토어, iOS 배포 인증서 등 전체 미구성).
- Trip 자동 종료(오프라인/타임아웃, Solid Queue) — `docs/future-improvements.md` 3번. 그 전에는 앱이 꺼져 종료를 못 누르면 운행이 서버에 열린 채 남는다(앱을 다시 켜면 위치 전송이 재개된다).

## 미검증 (실기기 QC 필요)

코드는 있지만 curl/`flutter analyze`·`flutter test` 수준까지만 검증됨 — 실기기/에뮬레이터로 아직 안 돌려봄.

- 온보딩 register 실패 케이스(서버 무응답/타임아웃/PIN 오류/잠금) SnackBar 노출.
- "운행 시작" 시 SDK 실패(위치 권한 거부 등) SnackBar 노출.
- 운행 시작·종료의 서버 연동 전체와 메인화면 "이전 · 현재 · 다음 정류장" 패널 — 시뮬레이터 위치를 정류장 순서대로 움직일 때 10초 주기로 갱신되는지(시험 절차는 README "iOS 시뮬레이터로 e2e 확인하기").
- 위치 전송 빈도(15m / 10초)로 30m 정류장 영역을 통과할 때마다 방문이 기록되는지 — **시뮬레이터에서는 확인함**(통과 10회, 40/40, [`docs/location-sampling-test.md`](../docs/location-sampling-test.md)). **실기기는 미검증**(GPS 오차·백그라운드·정차).
- 앱을 운행 중에 종료했다가 다시 켰을 때 위치 전송 자동 재개.
- **시스템 언어 자동 감지** — 코드(`lib/l10n/language_settings.dart`)에는 시스템 언어가 `ko`면 한국어, 아니면 영어로 하는 로직이 있지만 **동작을 확인하지 못했다.** 2026-10-24 시뮬레이터에서 시스템 언어를 일본어로 바꿨는데도 한국어로 보였다. 원인 후보는 설정 화면에서 직접 고른 언어(`language_override`)가 저장되어 우선 적용되는 것으로 보이나, 그 값을 지우고 다시 시험하지는 못했다. 감지가 실제로 안 되면 버그로 올린다. 확인 방법: 앱 데이터를 지우거나(`language_override` 삭제) 새로 설치한 상태에서 시스템 언어를 바꿔 본다.
- 어드민 "PIN 재발급" → 앱 "PIN으로 재등록" → 새 PIN으로 재등록 전체 흐름.

## 완료

- iOS 위치 권한 팝업 로컬라이제이션(`InfoPlist.strings` ko/en) — 시스템 언어를 따름, 앱 내 언어설정과 무관(OS 공통 동작). `NSMotionUsageDescription`은 미도입(`stopDetection: false`).
- Traccar Client SDK 연동(`init`/`start`/`stop`, 상태표시) — 실기기(SM-A516N)로 위치 도달 확인.
- 백엔드 API 5종 구현: `register`/`routes`(위 계약 참고), `Bus.pin`·`traccar_unique_id` 자동생성 + PIN 재발급, Admin "신규등록 운영자 지침" 페이지.
- driver_app register API 실연동 활성화 — `DriverRegistration.register()`가 `ApiClient.register()`를 실제로 호출하도록 원복, 실서버+실기기 e2e(PIN 입력 → register → deviceId 수신 → 메인화면 전환) 검증 완료.
- 차량 등록 시 Traccar device 자동 프로비저닝(`TraccarDeviceSync`) — `docs/traccar-integration.md` 로드맵 2단계.
- driver_app 설정화면 "PIN으로 재등록" → `TrackingController.forceStop()` + `DriverRegistration.clear()` 연결.
- Admin 차량/시·도/운행지역/노선/정류장 리스트·상세에 최종수정일자 표시.
- register PIN 1회용 처리 + 동시 요청 경쟁 상태 방지(원자적 조건부 UPDATE) — 위 register 계약 참고.
