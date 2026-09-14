# driver_app — 버스 운전자 앱 (Flutter)

[`where-is-my-bus`](../README.md) 모노레포의 일부입니다. 레포 루트는 Rails 웹 앱, 이 폴더는 운전자용 Flutter 앱입니다.

## 역할

- 운전자 단말에서 GPS 위치를 서버로 송신
- 정류장 크라우드소싱 등록

현재는 스캐폴드만 있는 상태이며, 그전까지는 공식 Traccar Client 앱으로 위치를 수집합니다 (`../docs/traccar-integration.md`).

목업 아티팩트 
https://claude.ai/code/artifact/cd691e97-db15-4998-8b02-6f44744d37bd?via=auto_preview


## 위치 송신: Traccar Client SDK

위치 추적 로직을 직접 구현하지 않고 공식 SDK로 UI만 감싼다.

- SDK: [`traccar_client_sdk`](https://pub.dev/packages/traccar_client_sdk) (pub.dev, Apache-2.0) — [traccar.org/traccar-client-sdk](https://www.traccar.org/traccar-client-sdk/) · [Flutter 문서](https://www.traccar.org/traccar-client-sdk-flutter/)
- 역할: 백그라운드 위치 수집 + 권한 요청(위치·배터리 최적화 예외) + OsmAnd 프로토콜(`:5055`)로 서버 전송까지 전부 처리. 앱은 UI(로그인/상태표시/시작·정지)만 구현.
- 초기화: `Config(serverUrl: <Traccar 서버>, deviceId: <buses.traccar_unique_id>, location: LocationConfig(stopDetection: false))` → `tracker.start()`. `stopDetection`은 반드시 `false` — 켜면 iOS 모션 권한이 딸려온다(`ISSUE.md` 참고).
- SDK 범위 밖(직접 구현 필요): 정류장 크라우드소싱 등록 화면, iOS `Info.plist` 위치 권한 문구(`NSLocationAlwaysAndWhenInUseUsageDescription`).

## 다국어 (한국어/English)

`intl`/ARB 코드생성 대신 record 기반 자체 구현(`lib/l10n/app_strings.dart`) — 2개 언어뿐이라 코드생성 스텝 없는 쪽이 가벼움. 참고: `xenoNote/Dev_knowledge/setup/flutter_app_polish_patterns.md` §10·§11.

- `lib/l10n/language_settings.dart` — 언어 선택을 `SharedPreferences`로 영속화. 저장된 값이 없으면(최초 실행) 시스템 언어를 자동 감지(`ko`→한국어, 그 외 전부→English 폴백).
- `lib/l10n/app_strings.dart` — 화면별 문구를 `(ko:, en:)` record로 정의, `AppStrings.xxx`로 조회.
- 설정화면 "언어" 항목에서 시스템 기본값/한국어/English를 명시적으로 고를 수 있음(고르면 재실행 후에도 유지).
- 언어가 3개 이상으로 늘어나면 표준 `flutter gen-l10n`/ARB 파이프라인으로 전환 검토.

### 제작 체크리스트

- [x] 패키지 ID를 `com.tenminutestudio.whereismybusdriver.*`로 변경 (Android `applicationId`/`namespace`, iOS bundle ID)
- [x] UI 목업 확정 — 스플래시/온보딩/메인/설정/상태보기 5화면 (`mvp-spec.md`, Artifact 목업)
- [x] 다국어(한국어/English) 인프라 구성 — `lib/l10n/app_strings.dart`·`language_settings.dart`, 설정화면 언어 전환 스텁까지 (`flutter analyze`/`flutter test` 통과)
- [x] 서비스 화면 flutter 생성/정리
- [x] `pubspec.yaml`에 `traccar_client_sdk` 의존성 추가 (`flutter pub add traccar_client_sdk`)
- [x] iOS `Info.plist`에 위치 권한 문구 추가(모션 권한은 불필요 — `stopDetection: false`로 끄기로 결정, `ISSUE.md` 참고) + `CFBundleLocalizations`(`ko`/`en`) 등록 + 언어별 `InfoPlist.strings`, Background Modes(Location updates) 활성화 (macOS/Xcode가 없는 환경에서 작업해 `project.pbxproj` 등록까지는 했으나 실제 빌드로 검증은 못함 — Mac에서 한 번 열어 Copy Bundle Resources에 `InfoPlist.strings`가 보이는지 확인 필요)
- [ ] 온보딩 화면 실제 구현: adminUrl+PIN 입력 → `POST /integrations/traccar/register` 호출 (서버 엔드포인트 자체도 미구현, `ISSUE.md` 참고)
- [x] `tracker.init(Config(location: LocationConfig(stopDetection: false), serverUrl, deviceId))` → `start()` / `stop()` 연결, 상태 표시(`isTracking()`) — `lib/tracking_controller.dart`. `LocationConfig`는 mvp-spec "위치 추적 고정값" 표대로 설정(accuracy HIGH/distanceMeters 30/intervalSeconds 30/heartbeatIntervalSeconds 30). `serverUrl`은 register API 미구현이라 임시 테스트 서버(`yehyunserver.iptime.org:5055`, OsmAnd 프로토콜 포트) 고정값 사용 중, API 붙으면 `DriverRegistration` 응답값으로 교체 필요. `init()`은 최초 "운행 시작" 탭에서 지연 호출하도록 구현됨(스플래시/온보딩에서 미리 부르지 않음). `heartbeatIntervalSeconds: 30` 사용에 필요한 iOS `UIBackgroundModes`(`fetch`)/`BGTaskSchedulerPermittedIdentifiers` 등록 완료(`Info.plist`)
- [x] Android 최초 실행 시 SDK가 띄우는 배터리 최적화 예외 팝업 동작 확인
- [x] 실기기로 Traccar 서버(임시 테스트 서버 `yehyunserver.iptime.org:5055`)에 위치 도달 확인 — SM-A516N 실기기로 완료
  - register API가 없어 `DriverRegistration.register()`가 `deviceId = "{온보딩 서버주소 입력값에서 http(s):// 뗀 것}-1a2b3c"`로 결정론적 생성(`lib/driver_registration.dart`) — 테스트 전에 Traccar 관리화면(`yehyunserver.iptime.org:8082`)에서 이 값으로 디바이스를 먼저 등록해둬야 위치가 조용히 무시되지 않음
  - 예: 온보딩 서버주소 칸에 `test` 입력 → `deviceId = test-1a2b3c` → Traccar 디바이스 Identifier에 동일하게 등록
  - `flutter run`(또는 릴리즈 APK 설치) → 온보딩(더미, PIN 검증 없음) → 메인에서 "운행 시작" 탭 → Traccar 서버 디바이스 목록/지도에서 해당 deviceId로 위치 수신 확인
  - Android 실기기 권한 팝업 순서(정상 동작, 이 4개 외 추가로 뜨면 이상 신호): ① 위치정보(포그라운드, 정확한 위치 포함) → ② 알림(`POST_NOTIFICATIONS`, 포그라운드 서비스 상주 알림용) → ③ 백그라운드 위치(`ACCESS_BACKGROUND_LOCATION`, API 30+부터 일반 팝업이 아니라 설정 화면 형태로 뜸 — "항상 허용" 라디오 선택 후 좌상단 뒤로가기로 앱 복귀해야 결과가 콜백됨, 자동 복귀 안 됨) → ④ 배터리 최적화 예외
  - Windows에서 빌드 시 프로젝트(E:)와 pub-cache/Gradle 홈(C:)이 다른 드라이브면 Kotlin incremental 컴파일러가 "different roots" 에러로 실패하는 버그 발견 — `android/gradle.properties`에 `kotlin.incremental=false`로 회피
  - Android는 `stopDetection: false`로도 `ACTIVITY_RECOGNITION`(신체활동) 권한 팝업이 뜨는 걸 발견 — 네이티브 라이브러리가 이 권한을 설정값과 무관하게 매니페스트에 항상 선언해둔 것(iOS는 `stopDetection`으로 막히지만 Android는 안 막힘). `AndroidManifest.xml`에 `tools:node="remove"`로 명시 제거(`ISSUE.md` 참고)
- [ ] 정류장 크라우드소싱 등록 화면(SDK 범위 밖, 별도 구현)
- [ ] 앱 아이콘/스플래시 이미지 자산 제작·적용 (패키지 ID는 이미 변경됨 — 아이콘 자체가 아직 기본 Flutter 로고)
- [ ] Firebase 연동 시 새 패키지 ID로 `google-services.json` / `GoogleService-Info.plist` 재발급
- [ ] 앱스토어/플레이스토어 배포 파이프라인 구성 (현재 미구성)
  - [ ] Android 릴리즈 키스토어 생성 + `build.gradle.kts` signingConfig 등록 (현재는 디버그 키로 릴리즈 빌드하는 Flutter 기본 스캐폴드 상태) — 키스토어 파일·store/key 비밀번호·alias를 레포 밖 안전한 곳에 백업 필수. 분실 시 같은 패키지 ID로 업데이트 영구 불가(fever2048 AOS 때와 동일 리스크)

### 백엔드(Rails) 개발 리스트

driver_app 코드만으로는 못 끝나는, 서버 쪽에서 먼저(또는 같이) 해야 하는 작업. 상세 근거는 [`ISSUE.md`](ISSUE.md#미구현-구현-필요).

- [ ] `POST /integrations/traccar/register` — PIN(`Bus.pin` 사용, `PinCode` 모델은 미사용) → `{ traccarServerUrl, deviceId }` 교환. 시도 횟수 제한(rate limit/lockout) 필수
- [ ] 배포별 `traccarServerUrl` 설정값 추가 — register 응답에 내려줄 값, credentials/ENV로 배포마다 다르게 주입(지역/국가별 인스턴스 대응)
- [ ] `Bus.traccar_unique_id` **자동 생성**으로 변경 — 버스 생성 시 Rails가 `SecureRandom.hex` 등으로 채움(수동입력 폐지, 추측 불가능성도 보장). 운영자는 생성된 값을 어드민 화면에서 복사해 Traccar 서버 등록화면에 붙여넣기만 하면 됨(양방향 수동입력 → 단방향 복붙으로 축소)
- [ ] `GET /integrations/traccar/routes`(가칭) — `deviceId`로 Bus 조회 → 활성 Route의 Stop 목록(이름/lat·lng/`avg_travel_seconds`) JSON 응답. "다음 정류장" 표시용, 후순위
- [ ] Admin: "신규등록 운영자 지침" 버튼/페이지 — 자동 프로비저닝(아래) 전까지는 Traccar 서버 등록이 수동이라, 그 절차(Rails가 자동 생성한 `traccar_unique_id`를 복사 → Traccar 서버 관리화면에 붙여넣기 — 값이 어긋나면 위치가 조용히 무시됨)를 안내하는 가이드
- [ ] `traccar-integration.md` 로드맵 2단계: 차량 등록 시 Traccar 디바이스 자동 프로비저닝(REST API) — **완전 후순위, 앱 파트 단독 결정 아님, 팀 논의 후 착수**. 위 수동 지침으로 당분간 대체

#### (임시) "신규등록 운영자 지침" 내용 초안

어드민 화면 구현 시 참고용 — 실제 문구/디자인은 어드민 담당자가 확정.

1. **Rails에서 버스 등록**
   - 어드민에서 차량 추가 시 `traccar_unique_id`는 자동 생성됨(직접 입력하지 않음)
   - 버스 상세화면에 표시된 이 값을 복사
2. **Traccar 서버에 디바이스 등록**
   - Traccar 서버 관리화면(`/settings/devices` 등) 접속
   - 새 디바이스 추가, Identifier에 1번에서 복사한 값을 그대로 붙여넣기
   - 두 값이 하나라도 다르면 위치가 도착해도 조용히 무시됨(에러 없이 누락) — 트래킹 안 되면 이 값 일치부터 확인
3. **PIN 확인**
   - 이 버스의 `pin`(어드민 폼에 표시됨)을 운전자에게 전달
   - 운전자는 driver_app 최초 실행 시 `adminUrl` + 이 `pin`으로 등록
4. **동작 확인**
   - 운전자가 앱에서 "운행 시작" 누른 후, Rails에서 해당 버스의 `Trip`/`GpsLog`가 쌓이는지 확인(대시보드 또는 DB)

> 2단계 자동 프로비저닝(위 항목) 도입 시 1번은 생략 가능해짐.

## 메타

| 항목 | 값 |
|---|---|
| 패키지명 (pubspec) | `whereismybusapp` |
| Android applicationId | `com.tenminutestudio.whereismybusdriver.AOS` |
| iOS bundle ID | `com.tenminutestudio.whereismybusdriver.iOS` |
| 지원 플랫폼 | iOS, Android |

## 개발

```bash
cd driver_app
flutter pub get
flutter run
```

[Flutter SDK](https://docs.flutter.dev/get-started/install) 필요.

## CI / 배포

- 레포 루트 CI(`.github/workflows/ci.yml`)는 Rails 전용이며 `driver_app/**` 변경은 무시합니다. Flutter용 CI 잡은 아직 없습니다.
- Rails 배포 이미지(Kamal)에는 포함되지 않습니다 (`.dockerignore`에서 제외).
- 앱 스토어 배포 파이프라인은 미구성.
