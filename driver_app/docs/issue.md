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
| `stopDetection` | true | **고정, 비노출** | 장시간 정차(종점 대기) 시 GPS 절전 — 기본값이 합리적 |
| `preferPlatformProviders` (Android) | false | **고정, 비노출** | 디버깅/OEM 우회용, 일반 운전자 UI에 노출 불필요 |
| `password`(로컬 설정화면 잠금 PIN) | 없음 | **기각** — 이미 운영자가 발급하는 PIN 기반 단말 등록 체계(온보딩)가 있어 개념이 겹치고 혼란만 줌. 단말이 회사 관리 하에 있다는 전제. | 운전자가 임의로 설정을 바꾸거나 추적을 끄는 게 실제 문제로 확인되면 재검토 |

- **재검토 조건**: 배터리·정차 관련 운영 이슈가 실제로 생기면 `stopDetection`부터.

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
- 위치·모션 권한 팝업(`NSLocationAlwaysAndWhenInUseUsageDescription`, `NSMotionUsageDescription`)은 OS 시스템 팝업이라 **앱의 `AppLanguage`/`LanguageSettings`(설정 > 언어)와 무관하게 기기 시스템 언어를 따른다** — 인앱 언어를 English로 바꿔도 이 팝업은 시스템이 한국어면 한국어로 뜸(모든 앱 공통 정상 동작).
- 지금은 이 메커니즘 자체가 하나도 안 세팅되어 있음 — 위치 권한 요청 붙일 때(온보딩/추적 시작 구현 단계) 두 단계를 순서대로 채워야 함(`flutter_app_polish_patterns.md` §2):
  1. `Info.plist`에 `CFBundleLocalizations`로 지원 언어(`ko`, `en`) 등록 — 이게 없으면 iOS가 `.lproj` 폴더를 아예 안 봄.
  2. `ios/Runner/ko.lproj`·`en.lproj`에 각각 `InfoPlist.strings` 생성, 두 언어 문구를 빠짐없이 채움(하나라도 누락되면 시스템 기본 로케일 폴백 문구가 뜸).
- iOS가 기기 시스템 언어로 자동 선택 — 앱 코드에서 별도 분기 불필요.

### 메인화면 "다음 정류장 + 소요시간" (후순위)
- **목적 재정의**: 내비게이션 용도가 아니라 **"위치가 노선상 올바르게 잡히고 있는지 확인"용**. 상태보기의 원시 좌표(`35.2285, 128.8894`)는 운전자가 봐도 맞는지 판단이 안 되는데, "다음 정류장: OO, 3분"은 즉시 눈으로 맞는지 틀린지 확인 가능 — 노선 매핑 오류·GPS 튐을 가장 빨리 눈치챌 수 있는 신호.
- **정류장/노선 데이터 출처는 Traccar가 아니라 Rails admin의 `Route`/`Stop`**(이름·lat/lng·sequence·`avg_travel_seconds`). Traccar는 GPS 좌표만 알고 노선 개념이 없음.
- **어드민 쪽 신규 작업 없음** — 버스에 노선/정류장이 이미 등록돼 있다면 데이터는 그대로 재사용. 필요한 건 **읽기 API 하나**: `GET /integrations/traccar/routes` 같은 신규 엔드포인트, `deviceId`(`traccar_unique_id`)로 Bus 조회 → 활성 Route의 Stop 목록을 JSON으로 응답. 인증은 기존 ingest 패턴(공유 토큰/deviceId) 재사용, 새 인증 체계 불필요.
- **계산은 서버 왕복 대신 클라이언트에서**: driver 앱이 트립 시작 시 정류장 목록을 한 번 받아 로컬 캐시 → 앱이 이미 갖고 있는 실시간(업로드 게이트 이전) GPS와 로컬에서 매칭해 가장 가까운 정류장/다음 정류장을 계산. 서버 라운드트립(새 폴링 엔드포인트 + 최대 30~40초 지연)보다 지연이 없고 구현도 단순함.
- **비목표**: 시민 화면(`stops#arrival`)의 정교한 구간 보간(`progress`) 로직까지 그대로 맞출 필요는 없음 — 운전자 본인용 참고 표시라 완전 일치가 필수는 아님.
- **우선순위**: 핵심 파이프라인(위치전송 시작/정지, 서버 적재)이 실제로 동작 확인된 뒤에 붙일 것. MVP 필수 아님.
