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
- 초기화: `Config(serverUrl: <Traccar 서버>, deviceId: <buses.traccar_unique_id>, location: LocationConfig(stopDetection: false))` → `tracker.start()`. `stopDetection`은 반드시 `false` — 켜면 iOS 모션 권한이 딸려온다(`docs/issue.md` 참고).
- SDK 범위 밖(직접 구현 필요): 정류장 크라우드소싱 등록 화면, iOS `Info.plist` 위치 권한 문구(`NSLocationAlwaysAndWhenInUseUsageDescription`).

## 다국어 (한국어/English)

`intl`/ARB 코드생성 대신 record 기반 자체 구현(`lib/l10n/app_strings.dart`) — 2개 언어뿐이라 코드생성 스텝 없는 쪽이 가벼움. 참고: `xenoNote/Dev_knowledge/setup/flutter_app_polish_patterns.md` §10·§11.

- `lib/l10n/language_settings.dart` — 언어 선택을 `SharedPreferences`로 영속화. 저장된 값이 없으면(최초 실행) 시스템 언어를 자동 감지(`ko`→한국어, 그 외 전부→English 폴백).
- `lib/l10n/app_strings.dart` — 화면별 문구를 `(ko:, en:)` record로 정의, `AppStrings.xxx`로 조회.
- 설정화면 "언어" 항목에서 시스템 기본값/한국어/English를 명시적으로 고를 수 있음(고르면 재실행 후에도 유지).
- 언어가 3개 이상으로 늘어나면 표준 `flutter gen-l10n`/ARB 파이프라인으로 전환 검토.

### 제작 체크리스트

- [x] 패키지 ID를 `com.tenminutestudio.whereismybusdriver.*`로 변경 (Android `applicationId`/`namespace`, iOS bundle ID)
- [x] UI 목업 확정 — 스플래시/온보딩/메인/설정/상태보기 5화면 (`docs/mvp-spec.md`, Artifact 목업)
- [x] 다국어(한국어/English) 인프라 구성 — `lib/l10n/app_strings.dart`·`language_settings.dart`, 설정화면 언어 전환 스텁까지 (`flutter analyze`/`flutter test` 통과)
- [x] 서비스 화면 flutter 생성/정리
- [x] `pubspec.yaml`에 `traccar_client_sdk` 의존성 추가 (`flutter pub add traccar_client_sdk`)
- [x] iOS `Info.plist`에 위치 권한 문구 추가(모션 권한은 불필요 — `stopDetection: false`로 끄기로 결정, `docs/issue.md` 참고) + `CFBundleLocalizations`(`ko`/`en`) 등록 + 언어별 `InfoPlist.strings`, Background Modes(Location updates) 활성화 — 순서·근거는 [`docs/issue.md`](docs/issue.md#ios-위치-권한-팝업-로컬라이제이션-infopliststrings) (macOS/Xcode가 없는 환경에서 작업해 `project.pbxproj` 등록까지는 했으나 실제 빌드로 검증은 못함 — Mac에서 한 번 열어 Copy Bundle Resources에 `InfoPlist.strings`가 보이는지 확인 필요)
- [ ] 온보딩 화면 실제 구현: adminUrl+PIN 입력 → `POST /integrations/traccar/register` 호출 (서버 엔드포인트 자체도 미구현, `docs/issue.md` 참고)
- [ ] `tracker.init(Config(location: LocationConfig(stopDetection: false), serverUrl, deviceId))` → `start()` / `stop()` 연결, 상태 표시(`isTracking()`). **`init()`은 스플래시/온보딩이 아니라 최초 "운행 시작" 탭 때 지연 호출** — SDK가 `init()` 시점부터 GPS 센서 구독을 시작해서, 미리 부르면 운전자가 버튼을 누르기 전부터 센서가 켜짐(`docs/issue.md` 참고). `stopDetection`은 반드시 `false`로 넘길 것(기본값 `true`면 iOS 모션 권한이 딸려옴, `docs/issue.md` 참고). mvp-spec 고정값의 `heartbeatIntervalSeconds: 30`을 쓰려면 iOS `UIBackgroundModes`에 `fetch` 추가 + `BGTaskSchedulerPermittedIdentifiers`에 `org.traccar.client.heartbeat` 등록도 같이 필요 ([traccar-client-sdk-flutter 문서](https://www.traccar.org/traccar-client-sdk-flutter/) 참고)
- [ ] Android 최초 실행 시 SDK가 띄우는 배터리 최적화 예외 팝업 동작 확인
- [ ] 실기기로 Traccar 서버(개발용 인스턴스 또는 `demo.traccar.org`)에 위치 도달 확인
- [ ] 정류장 크라우드소싱 등록 화면(SDK 범위 밖, 별도 구현)
- [ ] 앱 아이콘/스플래시 이미지 자산 제작·적용 (패키지 ID는 이미 변경됨 — 아이콘 자체가 아직 기본 Flutter 로고)
- [ ] Firebase 연동 시 새 패키지 ID로 `google-services.json` / `GoogleService-Info.plist` 재발급
- [ ] 앱스토어/플레이스토어 배포 파이프라인 구성 (현재 미구성)

### 백엔드(Rails) 개발 리스트

driver_app 코드만으로는 못 끝나는, 서버 쪽에서 먼저(또는 같이) 해야 하는 작업. 상세 근거는 [`docs/issue.md`](docs/issue.md#미구현-기각-아님-구현-필요).

- [ ] `POST /integrations/traccar/register` — PIN → `{ traccarServerUrl, deviceId }` 교환. 시도 횟수 제한(rate limit/lockout) 필수
- [ ] Admin: 버스별 QR 코드 생성 화면(`{ adminUrl, pin }` 인코딩) — `rqrcode` 등, 후순위(온보딩은 수동입력으로도 동작)
- [ ] `GET /integrations/traccar/routes`(가칭) — `deviceId`로 Bus 조회 → 활성 Route의 Stop 목록(이름/lat·lng/`avg_travel_seconds`) JSON 응답. "다음 정류장" 표시용, 후순위
- [ ] `traccar-integration.md` 로드맵 2단계: 차량 등록 시 Traccar 디바이스 자동 프로비저닝(REST API)

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
