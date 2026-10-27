---
name: traccar-sync
description: "Modify Rails↔Traccar integration code — when creating or modifying Route/Stop/RouteStop/Bus admin controllers (app/controllers/admin/), app/services/*_registration.rb, app/services/traccar_*.rb, app/services/concerns/traccar_api_client.rb, StopVisitRecorder, or Integrations::{Traccar,TraccarEvents,Trips}Controller (register/bus/events/trips), or when dealing with bugs related to Traccar integration, geofence/group/device/permission — always use this skill. Key principles: complete rollback policy (TraccarRegistration), event ingest 200-ack contract (인증 실패 401 제외), Result pattern, WebMock test patterns."
---

## 이 스킬이 다루는 상황

Rails와 Traccar 서버(Docker) 사이의 정합성. 수정 대상은 세 부분이다:
① admin CRUD와 그것이 거치는 `*Registration` → `Traccar*` sync 서비스, ② 머신 간 수신 API(`integrations/*`), ③ 공통 클라이언트(`TraccarApiClient` concern).
설계 원본은 `docs/traccar-integration.md`(자원 대응·이벤트 흐름·설정·실측 동작), 결정 근거는 `docs/design-event-driven-rewrite.md` — 큰 변경 전에 먼저 읽는다. **Rails는 GPS 좌표를 저장하지 않는다.** Traccar가 Geofence 이벤트를 만들어 포워딩하고 Rails는 그것을 방문 기록(`StopVisit`)으로 남길 뿐이다.

## Traccar 자원 ↔ Rails 모델 (노선 단위 Group 간접 연결)

| Rails | Traccar | 담당 |
|---|---|---|
| `Route` (`traccar_group_id`) | 기기 group, 이름 = 노선명 | `RouteRegistration` → `TraccarGroupSync` |
| `Stop` (`traccar_geofence_id`) | geofence, 정류장 중심 30m 정사각형, 이름 = 정류장명 | `StopRegistration` → `TraccarGeofenceSync` |
| `RouteStop` (노선에 정류장 추가) | `POST/DELETE /api/permissions` — group ↔ geofence 연결 | `RouteStopRegistration` → `TraccarRouteStopLink` |
| `Bus` (`traccar_device_id`, `traccar_unique_id`) | device | `BusRegistration` → `TraccarDeviceSync` |
| `buses.route_id` (노선 배정) | device의 `groupId`를 노선 group으로 (해제 시 `NO_GROUP = 0`) | `BusRegistration` → `TraccarDeviceGroup` |
| `Trip` 시작·종료 | **없음** — Traccar를 부르지 않는다 | `TripStarter`, `TripFinisher` |

"geofence ↔ device"를 개별로 연결하는 코드를 만들지 않는다. geofence는 그 group에 속한 device의 이벤트만 받는다 — 그래서 어느 노선 버스가 정류장을 지나갔는지를 이벤트만으로 구분할 수 있다(노선에 없는 정류장 영역을 지나도 이벤트가 오지 않는다). 한 정류장이 여러 노선에 속하면 같은 geofence가 여러 group에 연결된다.

## 핵심 정책: 완전 롤백 (`TraccarRegistration`)

Route/Stop/RouteStop/Bus의 생성·수정·삭제는 **Rails 변경과 Traccar 호출을 한 트랜잭션**으로 묶는다(`TraccarRegistration`의 `create`/`update`/`destroy`). Traccar 호출이 실패하면 Rails 변경도 롤백한다. "Traccar 측 선행조건이 없으면 Rails 레코드도 없다."

- 저장은 `record.save` → `sync`, 삭제는 `record.destroy` → `unsync` 순서이며 **어느 쪽이 실패해도 `ActiveRecord::Rollback`**. 삭제는 DB가 먼저라서 `restrict_with_error`(이력) 때문에 거부되면 Traccar 자원은 건드리지 않는다.
- 새 모델을 Traccar와 묶으려면 `TraccarRegistration`을 상속해 `manages 모델, with: Traccar서비스`로 선언한다. 호출 방식이 다르면 `sync`/`unsync`를 재정의한다(`BusRegistration`, `RouteStopRegistration` 참고). 컨트롤러에서 `save`와 Traccar 호출을 직접 풀어 쓰지 않는다.
- **먼저 commit하고 Traccar를 나중에 호출하는 구조로 바꾸지 않는다.** 롤백 후 재시도가 막히는 버그의 원인이었다.
- `BusRegistration#sync`는 device sync 뒤 배정된 노선이 있으면 `TraccarDeviceGroup.assign`, 배정이 풀렸으면 `clear`를 호출한다. 그래서 **운행 시작·종료가 Traccar와 무관**하고 Traccar 장애 중에도 운전자는 운행을 시작·종료할 수 있다. 이 분리를 깨서 `Trip*`에서 Traccar를 부르게 하지 않는다.
- ⚠️ **외부 HTTP는 롤백되지 않는다.** Traccar 생성은 성공했는데 응답 파싱 실패(`JSON::ParserError`)로 failure가 반환되면 Rails 레코드는 롤백되고 Traccar에만 자원이 남는 orphan이 생긴다. 이 경우 Rails 레코드가 없으므로 sync 액션으로 복구할 수 없다 — Traccar 콘솔에서 삭제하거나 별도 reconciliation이 필요하다.
- Rails 레코드와 Traccar ID는 남아 있는데 Traccar 쪽 상태가 어긋난 경우는 admin 수동 sync 액션으로 복구한다: `sync_group`(routes) / `sync_geofence`(stops) / `sync_device`(buses). id가 남은 채 Traccar 자원이 이미 삭제됐다면 sync가 update(PUT) 분기로 가서 실패한다 — Rails 콘솔에서 해당 `traccar_*_id`를 nil로 리셋한 뒤 sync(create 경로)를 실행한다. group을 다시 만들었다면 각 노선 정류장의 permission 연결은 `RouteStop`을 다시 등록(제거 후 추가)해야 복원된다.
- `RouteStop`은 생성·삭제만 지원한다. 정차 순서 변경(update)은 미지원이다(`docs/future-improvements.md` 11번).
- 트레이드오프: Traccar 서버가 죽으면 **Traccar sync가 필요한 admin 작업**(노선·정류장·정차·차량의 생성·수정·삭제, 노선 배정 변경)이 실패하고 화면에 사유가 표시된다. 운행 시작·종료와 승객 화면은 계속 동작한다. 실패는 `render_failure`로 422 + 폼 에러 표시(Result failure)이며 예기치 않은 예외까지 막지는 않는다.

## TraccarApiClient (`app/services/concerns/traccar_api_client.rb`)

- 모든 sync 서비스가 include한다. `Result = Struct.new(:success, :error, keyword_init: true)` + `failure?` — **`success?`는 정의돼 있지 않다**(`result.success` 직접 확인). 단 `TraccarRegistration::Result`는 `success?`/`failure?`를 가진다(두 Result를 혼동하지 않는다).
- 서비스는 예외를 던지지 않고 `RESCUED_ERRORS`를 rescue해서 failure Result를 반환한다. 새 오류 종류가 생기면 목록에 추가한다.
- 접속 정보: **환경변수 → credentials 순서**. `TRACCAR_API_BASE_URL`, 인증은 `TRACCAR_API_TOKEN`(Bearer, Traccar `web.serviceAccountToken`)이 있으면 그것을, 없으면 `TRACCAR_API_EMAIL`/`PASSWORD` 기본 인증. `base_url`이 비면 `CredentialsMissing`(→ failure Result).
- `request()`는 non-2xx이면 `raise "Traccar API #{method} #{path} → #{code}"`를 던지고 서비스의 rescue가 받는다.
- 테스트는 클래스메서드 `stub_credentials(base_url:, token: nil, email: nil, password: nil)`로 주입한다.

## 수신 API 계약 (`Integrations::*`, `ActionController::API`)

| 엔드포인트 | 규칙 |
|---|---|
| `POST /integrations/traccar/events` | Traccar 이벤트 포워딩. `X-Ingest-Token` 헤더(timing-safe), 실패 `401`(토큰 미설정이면 전부 401, fail-closed). **인증 성공 후에는 기록하지 않는 이벤트도 `200` + `{ status, reason }`로 ack** — 4xx면 Traccar 포워딩이 재시도 폭주한다. 이 원칙은 방어적 관례가 아니라 계약이다 |
| `POST /integrations/traccar/register` | `{ pin }` → `200 { traccarServerUrl, deviceId, busNumber, licensePlate, route }`. `401` PIN 불일치 / `409` PIN 소모 / `429` IP당 5회 실패 → 15분 잠금(`Rails.cache`). PIN은 조건부 UPDATE(`pin_registered_at: nil` → 현재 시각)로 원자적 소모 — 이 한 줄을 풀어써서 경쟁 상태를 만들지 않는다 |
| `GET /integrations/traccar/bus?deviceId=` | `{ busNumber, licensePlate, route, activeTrip }`. `404 unknown_device` |
| `POST /integrations/traccar/trips/start` | `{ deviceId }` → `{ trip }`. 이미 운행 중이면 같은 운행을 돌려준다(멱등). 배정 노선 없으면 `422 no_route_assigned`, 없는 기기 `404` |
| `POST /integrations/traccar/trips/end` | `{ deviceId }` → `{ ended }`. 진행 중 운행이 없어도 `200`(재시도 멱등) |

- 이벤트 처리는 `StopVisitRecorder`: `geofenceEnter`/`geofenceExit`만 처리하고, 단말 → Bus·geofence → Stop·`bus.active_trip` 조회 후 방문을 기록한다. 기록하지 않는 사유는 모두 `ignored` + `reason`(`unsupported_type`, `invalid_payload`, `unknown_device`, `unknown_geofence`, `no_active_trip`, `before_trip_start`, `stop_not_on_route`, `duplicate`, `already_inside`, `no_open_visit`). 새 사유를 추가해도 상태 코드는 200이다. 이벤트 중복은 `entered_event_id`/`exited_event_id` 유니크 인덱스(`"{id}@{eventTime}"` 키)가 막는다.
- `TripFinisher`는 종료 때 열린 방문 기록을 종료 시각으로 닫는다(마지막 정류장 이탈 이벤트가 종료보다 늦게 오면 무시되기 때문).
- ⚠️ `deviceId`(= `traccar_unique_id`)만으로 운행 시작·종료를 인증한다. 기기별 토큰은 후속 과제(`docs/future-improvements.md` 2번).
- 설정 우선순위: `ENV["TRACCAR_INGEST_TOKEN"]` → `credentials[:traccar][:ingest_token]` → **`Rails.env.local?`일 때만** 개발 기본값(`dev-traccar-token`). 운영 미설정이면 fail-closed. `traccarServerUrl`은 `ENV["TRACCAR_SERVER_URL"]` → credentials → 로컬 `http://localhost:5055`.
- 실측 동작(위치 시각이 과거면 이벤트가 안 만들어짐, permission 중복 POST 허용, 서비스 토큰 계정은 목록 API가 비어 있음 등)은 `docs/traccar-integration.md` "알아둘 동작".

## 테스트 패턴 (Minitest + WebMock)

```ruby
class TraccarGroupSyncTest < ActiveSupport::TestCase
  setup do
    TraccarGroupSync.stub_credentials(base_url: "http://traccar.test", token: "test-token")
  end

  test "creates a group when route has no traccar_group_id" do
    stub_request(:post, "http://traccar.test/api/groups")
      .with(body: { name: route.name }.to_json)
      .to_return(status: 200, body: { id: 42 }.to_json, headers: { "Content-Type" => "application/json" })

    result = TraccarGroupSync.call(route)

    assert result.success
    assert_equal 42, route.reload.traccar_group_id
  end
end
```

- 서비스 실패 케이스는 **예외가 아니라 failure Result + DB 무변경**을 단언한다. `*Registration` 테스트는 Traccar 실패 시 Rails 레코드가 롤백됨(생성은 `count` 불변, 삭제는 레코드 유지)을 단언한다.
- `test_helper.rb`가 `WebMock.disable_net_connect!(allow_localhost: true)` — 실 Traccar 서버로 나가는 테스트는 없다.
- 수신 API 테스트는 WebMock이 불필요하다(수신 쪽) — status/헤더/payload 계약과 `StopVisitRecorder`의 `ignored` 사유 위주. 위치: `test/controllers/integrations/`, `test/services/`.

## 검증

```bash
bin/rails test test/services/ test/controllers/integrations/ test/controllers/admin/
bin/rails test                   # 전체 (262건 기준)
```

- **CI에는 테스트 잡이 없다** — `bin/ci`는 rubocop/audit/brakeman만 돈다. 테스트는 반드시 로컬에서 실행하고 확인한 뒤 완료를 선언한다.
- 실제 Traccar와 붙여 보려면 `docker compose up -d --build` 후 `bin/rails "demo:drive[1번]"`(`docs/local-demo.md`).

## 성공 기준

- admin CRUD에서 Traccar 호출 실패 시 Rails DB가 커밋되지 않는다(테스트로 증명).
- 이벤트 수신은 토큰 인증 실패(`401`)를 제외하면 항상 200-ack — 알 수 없는 단말·지오펜스·운행 없음에 4xx를 반환하지 않는다.
- 운행 시작·종료 경로에서 Traccar를 호출하지 않는다.
- 서비스는 예외 대신 failure Result를 반환하고, 새 예외 유형은 `RESCUED_ERRORS`에 있다.
- geofence ↔ device 개별 연결 코드가 새로 생기지 않았다.
- 로컬에서 관련 테스트가 전부 통과한다.

## 열린 질문

- 운전자가 종료를 누르지 않으면 Trip이 계속 열린다 — 자동 종료 기준 미정(`docs/policy-draft.md`, `docs/future-improvements.md` 3번).
- 운행 시작이 정류장 안에서 이뤄지면 진입 이벤트가 없어 첫 이탈이 `no_open_visit`로 무시될 수 있다(`docs/future-improvements.md` 20번).
