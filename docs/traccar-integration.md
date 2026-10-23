# Traccar 연동 개요

오픈소스 GPS 서버 [Traccar](https://www.traccar.org/)가 버스 위치를 받아 **정류장 Geofence 진입/이탈 이벤트**를 만들고,
Rails가 그 이벤트를 받아 "버스가 어느 정류장에 있는가"를 기록한다. Rails는 GPS 좌표를 저장하지 않는다.

설계 결정과 근거는 `docs/design-event-driven-rewrite.md`, 실행 방법은 `docs/local-demo.md`.

## 역할 분담

| 구성 요소 | 하는 일 |
|---|---|
| 운전자 앱 (`driver_app`) | PIN으로 기기 등록, 운행 시작·종료(노선은 차량에 배정된 것), `traccar_client_sdk`로 GPS를 Traccar에 전송. 새 API를 쓰도록 앱을 고치는 일은 아직 하지 않았다 (`docs/future-improvements.md` 21번) |
| Traccar | 위치 수신, 기기가 속한 그룹의 Geofence 진입/이탈 판정, 이벤트를 Rails로 포워딩 |
| Rails | 노선·정류장·차량 관리와 Traccar 자원 동기화, 운행 관리, 이벤트 → 방문 기록, 승객 화면 |

## Traccar 자원과 Rails 모델의 대응

| Rails | Traccar | 만드는 곳 |
|---|---|---|
| `Route` | 기기 그룹 (`traccar_group_id`) | `RouteRegistration` |
| `Stop` | Geofence, 30m 정사각형 (`traccar_geofence_id`) | `StopRegistration` |
| `RouteStop` (노선에 정류장 추가) | 그룹 ↔ Geofence 권한 연결 | `RouteStopRegistration` |
| `Bus` | 기기 (`traccar_device_id`, 식별자 `traccar_unique_id`) | `BusRegistration` |
| `Bus`에 노선 배정(`buses.route_id`) | 기기를 그 노선의 그룹으로 이동 (배정을 풀면 그룹에서 뺌) | `BusRegistration` (노선 화면의 배정 포함) |
| `Trip` 시작·종료 | 없음 — Traccar를 부르지 않는다 | `TripStarter`, `TripFinisher` |

모든 등록·삭제는 Rails 변경과 Traccar 호출을 한 트랜잭션으로 묶는다. Traccar가 실패하면 Rails 변경도 취소된다.
운전자의 운행 시작·종료는 Traccar를 부르지 않으므로 Traccar 장애와 무관하게 동작한다.

## 이벤트 흐름

1. 관리자가 차량에 노선을 배정하면 기기가 그 노선 그룹으로 옮겨진다. 앱이 `POST /integrations/traccar/trips/start`로 운행을 시작하면 Rails가 배정된 노선으로 운행을 만든다.
2. 앱이 보낸 위치가 그 그룹에 연결된 Geofence에 들어가거나 나오면 Traccar가 `geofenceEnter`·`geofenceExit` 이벤트를 만든다.
3. Traccar가 `POST /integrations/traccar/events`로 이벤트를 포워딩한다 (`X-Ingest-Token` 인증).
4. `StopVisitRecorder`가 기기 → 버스, Geofence → 정류장을 찾아 진행 중인 운행에 방문 기록을 남기거나 닫는다.
5. 승객 화면은 운행별 최신 방문 기록으로 버스 위치를 계산한다 (`RouteBusStatuses`).

## Traccar 설정

`docker/traccar/traccar.xml`에서 아래 항목을 설정한다.

| 키 | 용도 |
|---|---|
| `web.serviceAccountToken` | Rails가 Traccar API를 호출할 때 `Authorization: Bearer` 토큰으로 쓴다. 별도 사용자 계정이 필요 없다 |
| `event.forward.url` / `.type` / `.header` | 이벤트를 Rails로 JSON으로 포워딩하고 `X-Ingest-Token` 헤더를 붙인다 |
| `database.*` | 데모는 기본 H2. 운영에는 권장되지 않는다 |

Rails 쪽 접속 정보는 환경변수가 credentials보다 우선한다.

| 환경변수 | 의미 |
|---|---|
| `TRACCAR_API_BASE_URL`, `TRACCAR_API_TOKEN` | Traccar API 주소와 서비스 토큰 (토큰이 없으면 `TRACCAR_API_EMAIL`/`PASSWORD` 기본 인증) |
| `TRACCAR_INGEST_TOKEN` | 이벤트 수신 토큰. `traccar.xml`의 `event.forward.header`와 같아야 한다 |
| `TRACCAR_SERVER_URL` | 운전자 앱에 내려주는 위치 전송 주소 (Traccar의 5055 포트) |

## 알아둘 동작 (실측)

- 위치 시각이 직전 위치보다 과거면 Traccar는 이벤트를 만들지 않는다.
- 같은 쌍을 `POST /api/permissions`로 다시 연결해도 오류가 아니다. `DELETE /api/permissions`는 JSON 본문으로 해제한다.
- 서비스 토큰 계정은 목록 API(`GET /api/devices` 등)가 비어 있다. ID로 직접 조회하는 호출만 동작한다.
- 이벤트 페이로드의 필드 구성은 `docs/design-event-driven-rewrite.md` 6절.

## 보안

- 이벤트 수신 엔드포인트는 공유 토큰 헤더를 필수로 요구한다 (운영에서는 Traccar 호스트 IP 제한과 속도 제한을 함께 둔다).
- `traccar_unique_id`는 추측할 수 없는 값이어야 한다. OsmAnd는 이 식별자만 알면 위치를 주입할 수 있다.
- 운행 시작·종료 API가 이 식별자만으로 인증하는 점은 후속 과제다 (`docs/future-improvements.md` 2번).
- Traccar 서비스 토큰과 수신 토큰은 운영에서 Rails credentials나 환경변수로 관리하고 커밋하지 않는다.
