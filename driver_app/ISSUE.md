# driver_app — 확정 설정값/근거

확정된 항목의 설정값과 한 줄 사유만 담는다. 전체 논의(대안/기각사유/재검토조건)는 비공개 내부 문서로 관리— 필요하면 팀 채널로 요청.

`mvp-spec.md`는 MVP 최초 정의 시점의 기준선(freeze)이라 이후 갱신하지 않는다. 확정/변경되는 내용은 이 파일과 `README.md`에 반영한다.

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

### interval / angle / heartbeat
UI 비노출, MVP 고정값 사용(`intervalSeconds`/`heartbeatIntervalSeconds` 30초, `angleDegrees` 0). 값 표는 `mvp-spec.md`의 "위치 추적 고정값" 참고. 재검토 조건: 배터리·정확도 이슈 시 `intervalSeconds`부터.

## 확정 동작

### `tracker.init()` 호출 시점
스플래시/온보딩이 아니라 **운전자가 최초로 "운행 시작"을 탭하는 순간** 호출(이후 인스턴스 재사용). SDK가 `init()` 시점부터 센서 구독을 시작하므로, 미리 부르면 "버튼 눌러야 위치가 작동한다"는 UI 인상과 실제 동작이 어긋남.

### 지속추적 문구 — 최선노력, 보장 아님
`AppStrings.keepTrackingSub`를 단정형("계속 전송")에서 최선노력 힌트("앱을 나가도 전송을 이어가요 · 기기가 종료하면 중단될 수 있어요")로 변경. OS 강제종료 시 Android/iOS 둘 다 전송이 끊길 수 있어 보장 문구는 부정확.

### 지속추적 토글 — 설정화면 이동 + 기본값 `true`
메인화면 토글 제거, 설정화면 "위치 추적" 그룹으로 이동. 기본값 `false`→`true` — 꺼지면 서비스 목적이 무력화되는데 비숙련 운전자가 별도로 켜야 한다는 걸 놓칠 수 있는 실패 케이스 제거.

## 미구현 (구현 필요)

- `POST /integrations/traccar/register` — PIN → `{ traccarServerUrl, deviceId }`. 시도 횟수 제한(rate limit/lockout) 필수.
- Admin: 버스별 QR 코드 생성 화면(후순위, 온보딩은 수동입력으로도 동작).
- `GET /integrations/traccar/routes`(가칭) — 노선/정류장 조회, "다음 정류장" 표시용, 후순위.
- `traccar-integration.md` 로드맵 2단계: 차량 등록 시 Traccar 디바이스 자동 프로비저닝.

## 완료

- iOS 위치 권한 팝업 로컬라이제이션(`InfoPlist.strings` ko/en) — 시스템 언어를 따름, 앱 내 언어설정과 무관(OS 공통 동작). `NSMotionUsageDescription`은 미도입(`stopDetection: false`).
