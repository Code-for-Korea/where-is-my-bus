# 드라이버 앱 MVP 스펙

서비스명: **로컬버스 알리미 (Where is My BUS)**

위치 추적 로직은 [`traccar_client_sdk`](../README.md#위치-송신-traccar-client-sdk)가 전부 처리하므로, 이 앱이 만드는 건 그 위에 얹는 UI뿐이다.

## 오픈소스 멀티테넌트 전제

이 앱은 하나의 회사 전용이 아니라, 다른 지자체·버스운행사·국가가 각자 자기 서버(버스어드민+Traccar를 Docker로 패키징)에 띄워 그대로 가져다 쓸 수 있어야 한다. 그래서 **서버 주소를 앱에 고정할 수 없다** — 최초 1회 온보딩에서 입력받는다.

## 화면 구성

### 0. 스플래시
- 앱 로고/서비스명 표시. 저장된 온보딩 결과가 있으면 `tracker.init()` 후 메인화면, 없으면 온보딩 화면으로.

### 1. 온보딩(최초 실행 시 1회)
- **MVP는 수동 입력 한 화면**: `adminUrl`, `pin` 텍스트 필드 두 개를 **같은 화면에서 함께** 입력받는다. PIN만 먼저 받고 서버주소를 나중에(설정에서) 받는 2단계 흐름은 쓰지 않는다 — PIN 검증 자체가 서버주소 없이는 불가능하기 때문.
- "등록" 탭 → 앱이 그 `adminUrl`로 `POST /integrations/traccar/register`에 `pin` 전송 → 서버가 PIN으로 `Bus`를 조회해 `{ traccarServerUrl, deviceId }` 응답 (엔드포인트 미구현 — [issue.md](issue.md#미구현-기각-아님-구현-필요) 참고). 실패 시 같은 화면에서 에러 표시 후 재입력.
- 응답값을 로컬에 저장하고 `tracker.init(Config(serverUrl: traccarServerUrl, deviceId))` 호출.
- **QR 스캔은 후순위**(admin의 QR 생성 화면이 먼저 있어야 함, [issue.md](issue.md#미구현-기각-아님-구현-필요) 참고) — 나오면 이 화면에 스캔 버튼만 추가, 스캔 결과로 같은 두 필드를 채워주는 방식.

### 2. 메인화면
- **위치전송 버튼** (화면 중앙, 크게) — 탭하면 `tracker.start()` / `tracker.stop()` 토글. 전송 중/중지 상태를 색상·아이콘으로 즉시 구분.
- **'지속추적' 토글** (하단) — 꺼짐: 앱이 포그라운드일 때만 전송. 켜짐: 백그라운드에서도 계속 전송(Android 포그라운드 서비스 알림 상주, iOS 백그라운드 모드).
- **설정 버튼** (우측 상단) — 설정화면으로 이동.

### 3. 설정화면
- **기기 식별자 정보** — `deviceId`(= `traccar_unique_id`) **읽기전용 표시**. 값 자체를 직접 입력하지 않고, 바꾸려면 "재등록" 버튼으로 온보딩 화면(0번)을 다시 띄움. 설정화면 자체는 서버 최초 입력 경로가 아님.
- **서버 URL 정보** — `adminUrl`/`traccarServerUrl` **읽기전용 표시**(같은 이유로 재등록을 통해서만 변경).
- **상태보기(로그)** — `tracker.getLogs()` 결과를 타임스탬프순 리스트로 표시. 마지막 전송 시각, 전송 성공/실패 이력 확인용.
- **언어** — 한국어/English 전환. 기본은 시스템 언어 자동 감지(`PlatformDispatcher.instance.locale`), 지원 목록 밖 언어는 English로 폴백. 명시적으로 고르면 그 값을 재실행 후에도 유지.
- 위치 정확도/거리는 서버(Traccar)가 아니라 SDK 로컬 설정이라 운전자가 조정할 대상이 아님 → UI 없이 [고정값](#위치-추적-고정값)으로 박는다. Advanced settings, 로컬 비밀번호 잠금도 MVP에 없음 — 사유는 [issue.md](issue.md) 참고.

### 4. 상태보기 화면
- 설정화면의 "상태보기" 진입점으로 여는 별도 화면(또는 하단 시트).
- `getLogs()` 로그 리스트 + 현재 추적 상태(`isTracking()`), 마지막 위치 좌표/시각.

## 위치 추적 고정값

Traccar 서버엔 표시/설정되지 않는 SDK 로컬 파라미터라 UI로 노출하지 않고 앱 코드에 상수로 고정한다. 5초 폴링(`arrival_polling_controller.js`)과 버스 주행 특성(도심 주행 초속 5~11m, 정류장 간격 촘촘), 운전자 단말이 대체로 차량 전원에 상시 연결된다는 점을 반영해 SDK 기본값보다 정확도 쪽으로 조정:

| 필드 | SDK 기본값 | 고정값 | 이유 |
|---|---|---|---|
| `accuracy` | MEDIUM | **HIGH** | MEDIUM(WiFi/셀타워)은 도로 위 정밀도 부족(진행바 튐). HIGHEST는 정밀도 이득 대비 배터리 소모만 큼 |
| `distanceMeters` | 75 | **30** | 30m면 이동 중 3~6초마다 갱신 — 5초 폴링과 맞물림. 75m는 정류장 간격 짧은 구간에서 계단식으로 튐 |
| `intervalSeconds` (정지 시 heartbeat) | 300 | **30** | 정류장/터미널 정차 중에도 5분 방치되면 화면이 멈춰 보임. 정지 중엔 GPS 픽스 자체가 적어 배터리 부담 적음 |
| `heartbeatIntervalSeconds` | 0 | **30** | 위와 동일한 이유로 백그라운드 heartbeat도 맞춤 |
| `angleDegrees` | 0 | **0(비활성 유지)** | 버스 추적엔 방향 변화 트리거 불필요 |
| `stopDetection`/`stopTimeoutSeconds` | true/60 | **기본값 유지** | 장시간 정차 시 GPS 절전 — 합리적인 기본값 |

## 검토했지만 채택 안 한 내용

Advanced settings 노출 범위, 푸시, 커스텀 동의 팝업, 로컬 PIN 잠금, "번호+PIN만으로 서버 자동 감지" 등 논의·기각 사유는 [`issue.md`](issue.md)에 정리했다.

## 관련 문서
- [`issue.md`](issue.md) — 논의/보류/기각 로그, 미구현 서버 API 목록
- [`../README.md`](../README.md) — SDK 연동 개요, 제작 체크리스트, 패키지 ID
- [`../../docs/traccar-integration.md`](../../docs/traccar-integration.md) — 서버 측 연동 설계(데이터 흐름, 보안, 로드맵)
