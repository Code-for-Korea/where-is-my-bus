# 드라이버 앱 논의 로그

`mvp-spec.md`는 "지금 뭘 만들지"만 담는다. 검토했지만 채택 안 한 것, 보류한 것, 왜 그렇게 결정했는지는 여기 남긴다. 새 논의가 생기면 항목을 추가한다.

## 기각

### 버스번호 + PIN만으로 서버 자동 감지
- **논의**: adminUrl 입력 없이 버스번호+PIN만 넣으면 서버까지 자동으로 찾아지게 할 수 없나?
- **기각 사유**: 이걸 성립시키려면 어딘가에 "번호+PIN → 어느 조직 서버인지" 매핑하는 **중앙 디렉토리 서버**가 필요한데, 이는 셀프호스팅 오픈소스 철학과 충돌한다 — 단일 장애점이자, 전 세계 배포판의 PIN을 한곳에 모아놓은 공격 표면이 된다. 중앙 디렉토리 없이는 애초에 기술적으로 불가능.
- **연결 이슈**: 버스번호는 차량 외부에 적혀 있어 공개 정보다. PIN이 4~6자리뿐이라 서버 하나로 범위를 좁혀도 무차별 대입에 약하다 → `register` 엔드포인트에 시도 횟수 제한(rate limit/lockout) 필수.
- **결론**: adminUrl은 QR(기본) 또는 수동 입력(대안)으로 명시적으로 받는다. → `mvp-spec.md` 온보딩 섹션 참고.

### 푸시(FCM/APNs)
- **논의**: 공식 traccar-client 앱은 Firebase Messaging으로 서버가 원격 `start`/`stop`/`factoryReset` 명령을 보낼 수 있게 되어 있음. SDK 자체 기능은 아니고 앱이 별도로 붙인 것.
- **기각 사유**: 이 프로젝트는 커스텀 ingest 구조라 서버 쪽 FCM 연동이 없다. '지속추적' 토글로 로컬 제어가 이미 충분.
- **재검토 조건**: 운영자가 현장 개입 없이 원격으로 추적을 켜고 꺼야 하는 실제 운영 이슈가 생기면.

### 위치정보 커스텀 동의 팝업
- **논의**: SDK `start()` 자체가 OS 권한 팝업을 자동으로 띄움(Android: SDK 내부 투명 액티비티, iOS: `Info.plist` 문구 기반 시스템 팝업).
- **기각 사유**: 커스텀 팝업 없이도 SDK 기본 흐름으로 충분. iOS "Always" 승격을 위한 사전 설명 화면은 승인율에 도움이 될 수 있으나 필수는 아님.

## 보류 (기본값 고정, 노출 안 함)

### 설정 > Advanced settings (공식 앱 기준 5개: buffer/wakelock/stopDetection/preferPlatformProviders/password)
공식 `traccar-client` 앱의 "고급 설정" 토글 하위엔 정확히 이 5개(안드로이드 전용 2개 포함)뿐이다. 항목별 판단:

| 항목 | 기본값 | MVP 판단 | 사유 |
|---|---|---|---|
| `buffer` (오프라인 버퍼링) | true | **고정, 비노출** | 끄는 옵션 자체가 의미 없음 — 항상 켜두는 게 맞음(전송 실패 시 재시도 큐) |
| `wakeLock` (Android) | false | **고정, 비노출** | 배터리 소모 큼, '지속추적' 토글로 UX 대체 |
| `stopDetection` | true | **고정, `false`로 끔** | (재검토 후 결정 변경 — 아래 참고) |
| `preferPlatformProviders` (Android) | false | **고정, 비노출** | 디버깅/OEM 우회용, 일반 운전자 UI에 노출 불필요 |
| `password`(로컬 설정화면 잠금 PIN) | 없음 | **기각** — 이미 운영자가 발급하는 PIN 기반 단말 등록 체계(온보딩)가 있어 개념이 겹치고 혼란만 줌. 단말이 회사 관리 하에 있다는 전제. | 운전자가 임의로 설정을 바꾸거나 추적을 끄는 게 실제 문제로 확인되면 재검토 |

- **재검토 조건**: 배터리·정차 관련 운영 이슈가 실제로 생기면 `stopDetection`부터(단, 켜면 아래 사유로 모션 권한이 다시 필요해짐을 감안).

#### `stopDetection` — 최초 판단(켜짐 유지) 재검토 후 끄기로 변경
- **최초 판단**(위 표, 지금은 유효하지 않음): 장시간 정차(종점 대기) 시 GPS 절전 — 기본값이 합리적이라 보고 켜둠.
- **재검토 계기**: `tracker.init()` 지연 초기화를 논의하며 SDK 소스(`core/src/iosMain/kotlin/org/traccar/client/PlatformModule.kt`)를 확인한 결과, `stopDetection: true`일 때만 `MotionActivityDetector`가 Koin에서 실제로 생성되고 iOS `CMMotionActivityManager`를 구독한다 — 즉 이 옵션을 켜두면 iOS에서 **모션(피트니스) 권한**(`NSMotionUsageDescription`)이 추가로 필요해진다.
- **결정**: `stopDetection: false`로 끈다. 버스 위치 전송 앱이 "피트니스 데이터에 접근하려 합니다" 팝업을 띄우면, 앱 정체를 모르는 운전자 입장에서 불신·오해를 살 리스크가, 장시간 정차 시 GPS를 계속 폴링해서 배터리를 더 쓰는 비용보다 크다고 판단. 이 프로젝트는 오픈소스로 누구나(다른 지자체·운영사) 가져다 쓰는 걸 전제해서, 앱 자체는 최소한의 직관적인 기능만 제공하는 쪽을 우선한다 — 배터리 문제는 앱이 아니라 운영 방식(상시 전원 연결 단말 사용, README 기술적 전제와 동일)으로 해결할 문제다.
- **영향**: iOS에서 `NSMotionUsageDescription` 자체가 필요 없어짐(`MotionActivityDetector`가 생성되지 않아 모션 API를 호출하지 않음) — `Info.plist`/`InfoPlist.strings`에서 제거.
- **재검토 조건**: 장시간 정차 구간에서 배터리 소모가 실제 운영 이슈로 확인되면, 모션 권한 프롬프트에 대한 사전 설명 UI를 먼저 검토한 뒤에만 다시 켤 것.

### 고급 토글 밖의 조건부 노출 항목 (interval / angle / heartbeat)
공식 앱은 이 셋을 "고급"이 아니라 조건부로 메인 설정 리스트에 노출한다(`interval`은 최고정확도이거나 Android에서 거리필터 0일 때만, `angle`은 최고정확도일 때만, `heartbeat`는 항상). 이 프로젝트는 셋 다 노출하지 않고 **MVP 고정값**으로 박는다 — 값은 `mvp-spec.md`의 "위치 추적 고정값" 참고 (`intervalSeconds`/`heartbeatIntervalSeconds` 30초, `angleDegrees` 0=비활성).
- **재검토 조건**: 배터리·정확도 관련 운영 이슈가 실제로 생기면 `intervalSeconds`부터.

## 미구현 (기각 아님, 구현 필요)

### `POST /integrations/traccar/register` (PIN → deviceId/traccarServerUrl 교환)
- 온보딩(QR/수동입력으로 adminUrl+PIN 확보 후) 단계에서 호출할 엔드포인트. 현재 Rails에 미구현.
- 요구사항: PIN으로 `Bus` 조회 → `{ traccarServerUrl, deviceId }` 응답. 시도 횟수 제한 필수(위 "서버 자동 감지" 기각 사유 참고).
- `traccar-integration.md` 로드맵 2단계("차량 등록 시 Traccar 디바이스 자동 프로비저닝")와 연결되는 작업.

### Admin: 버스별 QR 코드 생성 화면 (후순위)
- MVP는 온보딩 화면에서 `adminUrl`+`pin`을 **수동 입력**받는 것으로 시작한다(`mvp-spec.md` 0번 화면). QR은 그 위에 얹는 단축 입력 수단일 뿐이라 없어도 온보딩 자체는 동작한다 — 그래서 후순위.
- QR을 붙이려면 admin이 `{ adminUrl, pin }`을 인코딩한 QR을 **생성해서 보여주는 화면**이 먼저 있어야 한다. 지금 `admin/buses/show.html.erb`엔 PIN 텍스트만 노출됨(`app/views/admin/buses/show.html.erb:13-14`) — QR 없음.
- 필요 작업: QR 생성(서버사이드 gem, 예: `rqrcode`) + `adminUrl`은 그 배포 인스턴스의 공개 URL(`request.base_url` 등)로 조합.
- 운전자가 QR 재스캔(단말 교체·PIN 재발급)할 상황을 고려해, 필요시 PIN 재발급 버튼도 같이 검토.

### iOS 위치 권한 팝업 로컬라이제이션 (`InfoPlist.strings`)
- 위치 권한 팝업(`NSLocationAlwaysAndWhenInUseUsageDescription`, `NSLocationWhenInUseUsageDescription`)은 OS 시스템 팝업이라 **앱의 `AppLanguage`/`LanguageSettings`(설정 > 언어)와 무관하게 기기 시스템 언어를 따른다** — 인앱 언어를 English로 바꿔도 이 팝업은 시스템이 한국어면 한국어로 뜸(모든 앱 공통 정상 동작).
- 처리 완료: `Info.plist`에 `CFBundleLocalizations`(`ko`/`en`) 등록 + `ios/Runner/ko.lproj`·`en.lproj`의 `InfoPlist.strings`에 두 언어 문구 채움(`flutter_app_polish_patterns.md` §2 순서대로) + `project.pbxproj`에 리소스로 등록. macOS/Xcode 없는 환경에서 작업해 실제 빌드 검증은 못함 — Mac에서 확인 필요.
- `NSMotionUsageDescription`은 넣지 않는다 — `stopDetection: false`로 끄기로 결정해서 모션 권한 자체가 불필요(아래 "`tracker.init()` 호출 시점" 및 [보류 섹션의 `stopDetection`](#stopDetection--최초-판단켜짐-유지-재검토-후-끄기로-변경) 참고).
- iOS가 기기 시스템 언어로 자동 선택 — 앱 코드에서 별도 분기 불필요.

### `tracker.init()` 호출 시점 — 지연 초기화(최초 "운행 시작" 탭 때)
- **발견**: SDK 소스(`traccar/traccar-client-sdk`, `core/src/commonMain/kotlin/org/traccar/client/Tracker.kt`·`TrackerEngine.kt`) 확인 결과, GPS/모션 센서 구독은 `start()`가 아니라 **`Tracker` 인스턴스 생성 시점**(= 앱이 `tracker.init(Config(...))`을 부르는 순간)에 이미 시작된다. `TrackerEngine`의 `init` 블록이 위치소스·모션신호 구독 코루틴을 즉시 실행하고, `start()`/`stop()`은 내부 `enabled` 플래그만 토글 — 파이프라인은 `if (!enabled) return@collect`로 **수신된 값을 버릴 뿐 구독 자체는 계속** 돈다.
- **문제**: mvp-spec대로 스플래시에서 등록된 운전자면 매번 자동으로 `tracker.init()`을 부르면, 운전자가 "운행 시작"을 누르기 전부터(앱을 열기만 해도) GPS/모션 센서가 로컬에서 계속 동작하게 된다. 서버로 전송은 안 되지만("정지됨" 상태에선 `enabled=false`라 업로드 안 됨), "운행 버튼을 눌러야 위치가 작동한다"는 UI가 주는 인상과 실제 동작이 어긋난다.
- **결정**: `tracker.init()`을 스플래시가 아니라 **운전자가 최초로 "운행 시작"을 탭하는 순간**에 호출한다(그 뒤로는 인스턴스 재사용). 이 프로젝트는 오픈소스로 다양한 지자체·운영자가 가져다 쓰고, 앱 사용에 익숙하지 않은 운전자도 쓸 걸 전제하므로 "누르면 위치정보가 작동한다"는 명료함이, 최초 1회 수백ms~1초 내외의 init 지연보다 우선한다.
- **영향**: `mvp-spec.md`의 "저장된 온보딩 결과가 있으면 `tracker.init()` 후 메인화면"이라는 스플래시 서술은 이 결정으로 더 이상 유효하지 않음 — `tracker.init()` 관련 문구는 삭제하고 "메인화면으로"만 남긴다. 실제 연결 작업(`tracker.init(Config, ...)` → `start()`/`stop()`) 때 반영.

### 지속추적 문구 — 최선노력이지, 보장이 아님
- **문제**: 기존 문구("앱에서 나가도 백그라운드에서 계속 전송")는 단정형이라, 실제로는 보장할 수 없는 걸 약속하는 셈이다.
  - Android: 포그라운드 서비스(알림 상주)라 OS가 메모리 부족만으로 죽이진 않지만, 일부 OEM(샤오미·화웨이 등)의 공격적인 배터리 최적화나 사용자가 최근 앱 목록에서 완전히 스와이프해 종료하면 서비스도 같이 꺼짐.
  - iOS: Background Modes(Location)도 "최대한 유지"이지 절대 보장이 아님 — 사용자가 앱 스위처에서 위로 스와이프해 앱을 종료하면 위치 업데이트가 함께 중단됨.
  - 두 경우 다 운전자는 "지속추적을 켜뒀으니 계속 보내지겠지"라고 믿고 있는데 실제로는 멈춰 있는 상황이 생길 수 있다.
- **결정**: `AppStrings.keepTrackingSub` 문구를 단정형("계속 전송")에서 최선노력을 명시하는 힌트로 변경("앱을 나가도 전송을 이어가요 · 기기가 종료하면 중단될 수 있어요"). 실제로 뭔가를 더 구현하기보다(예: iOS Significant-Location-Change로 재기동, "앱을 스와이프해서 끄지 마세요" 안내 등은 범위 밖) 문구로 기대치를 정직하게 맞추는 선에서 마무리.
- **완화책**: 이미 있는 상태보기 화면의 "마지막 전송" 표시가, 실제로 멈췄는지 운전자·운영자가 확인할 수 있는 유일한 신호. 운영상 이슈가 반복되면 그때 "N분 이상 전송 없음" 같은 경고 UI를 추가하는 걸 검토.
- **재검토 조건**: 강제 종료로 인한 추적 중단이 실제 운영 이슈로 확인되면, 상태보기에 "마지막 전송 지연" 경고나 iOS Significant-Location-Change API를 통한 재기동을 검토.

### 지속추적 토글 — 메인에서 설정으로 이동 + 기본값 켜짐
- **문제 제기**: 지속추적은 꺼지는 순간 앱을 나가자마자 서버로 위치가 안 가게 되는데, 이게 메인 화면 토글(세션마다 눈에 띄는 선택지)로 놓여 있으면 (a) 운전자가 실수로 꺼둔 채 운행할 위험, (b) "항상 켜져 있어야 하는 값"인데 매번 결정해야 하는 것처럼 보이는 UI 모순이 있었다.
- **결정**:
  1. 토글 자체를 메인화면에서 빼고 **설정화면 "위치 추적" 그룹**으로 옮긴다 — 세션마다 만지는 조작이 아니라 기기/운영 설정 성격이라 Settings가 맞는 자리. SDK(`Config`/`updateConfig()`)엔 이 값이 특정 화면에 있어야 한다는 제약이 없음(순수 데이터 필드) — 확인 완료.
  2. 메인화면엔 토글 대신 고정 안내문만 노출: "앱을 나가도 위치 전송이 지속됩니다. 단, 원활한 버스위치 정보 전송을 위해서는 기기를 전원에 연결하고, 운행중에는 앱 화면을 켜두시길 권장합니다." — 동작을 설명하고 운영 팁(상시 전원 연결, 화면 켜두기)을 같이 전달.
  3. 기본값을 `false`→**`true`**로 변경 — 지속추적이 꺼져 있으면 서비스 목적 자체가 무력화되는데, 비숙련 운전자가 "운행 시작" 버튼 하나만 누르고 별도로 설정에 들어가 두 번째 스위치까지 켜야 한다는 걸 놓칠 수 있는 실패 케이스를 없앤다. 끄는 건 여전히 가능(상시 화면 고정 등 특수 운용).
- **목적 재정의**: 내비게이션 용도가 아니라 **"위치가 노선상 올바르게 잡히고 있는지 확인"용**. 상태보기의 원시 좌표(`35.2285, 128.8894`)는 운전자가 봐도 맞는지 판단이 안 되는데, "다음 정류장: OO, 3분"은 즉시 눈으로 맞는지 틀린지 확인 가능 — 노선 매핑 오류·GPS 튐을 가장 빨리 눈치챌 수 있는 신호.
- **정류장/노선 데이터 출처는 Traccar가 아니라 Rails admin의 `Route`/`Stop`**(이름·lat/lng·sequence·`avg_travel_seconds`). Traccar는 GPS 좌표만 알고 노선 개념이 없음.
- **어드민 쪽 신규 작업 없음** — 버스에 노선/정류장이 이미 등록돼 있다면 데이터는 그대로 재사용. 필요한 건 **읽기 API 하나**: `GET /integrations/traccar/routes` 같은 신규 엔드포인트, `deviceId`(`traccar_unique_id`)로 Bus 조회 → 활성 Route의 Stop 목록을 JSON으로 응답. 인증은 기존 ingest 패턴(공유 토큰/deviceId) 재사용, 새 인증 체계 불필요.
- **계산은 서버 왕복 대신 클라이언트에서**: driver 앱이 트립 시작 시 정류장 목록을 한 번 받아 로컬 캐시 → 앱이 이미 갖고 있는 실시간(업로드 게이트 이전) GPS와 로컬에서 매칭해 가장 가까운 정류장/다음 정류장을 계산. 서버 라운드트립(새 폴링 엔드포인트 + 최대 30~40초 지연)보다 지연이 없고 구현도 단순함.
- **비목표**: 시민 화면(`stops#arrival`)의 정교한 구간 보간(`progress`) 로직까지 그대로 맞출 필요는 없음 — 운전자 본인용 참고 표시라 완전 일치가 필수는 아님.
- **우선순위**: 핵심 파이프라인(위치전송 시작/정지, 서버 적재)이 실제로 동작 확인된 뒤에 붙일 것. MVP 필수 아님.
