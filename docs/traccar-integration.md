# Traccar 위치 추적 연동 설계

오픈소스 GPS 추적 서버 [Traccar](https://www.traccar.org/)로 버스 위치를 수집하고, 기존 시민 서비스의 도착정보(ETA·진행바)에 반영한다.

## 결정 사항 (MVP)

1. **운전자 단말**: ~~공식 Traccar Client 앱~~ → **커스텀 앱 `driver_app`(Flutter)** 으로 대체.
   `driver_app`은 UI(온보딩/운행 시작·정지/상태표시)만 구현하고, 위치 수집·전송은
   [`traccar_client_sdk`](https://www.traccar.org/traccar-client-sdk-flutter/)에 그대로 위임한다.
2. **실시간 방식**: 기존 **폴링 유지**(`arrival_polling_controller.js`, 5초). Solid Cable 도입은 보류.
3. **지도**: 시민 화면은 **진행바만 유지**. 별도 지도 없음.

## 데이터 흐름

```
운전자 폰 (driver_app → traccar_client_sdk, OsmAnd :5055)
   └─ GPS(id·lat·lon) ─▶ Traccar 서버 (Docker, API :8082)
                              └─ 위치 포워딩(JSON POST) ─▶ Rails  POST /integrations/traccar/positions
                                                              └─ Bus 매핑 → Trip → GpsLog 적재
                                                                    └─ 기존 stops#arrival(폴링)이 읽어 시민 웹에 표시
```

## 운전자 온보딩 (driver_app, 구현 완료 — e2e 검증됨)

Admin에서 차량을 등록하면 Rails가 `traccar_unique_id`(추측 불가능한 식별자)와 `pin`(6자리)을
자동 생성하고, 같은 시점에 [Admin geofence/group 자동화](#admin-geofencegroup-자동화-구현-완료--노선-배차-연동)
절에서 다루는 `TraccarDeviceSync`가 이 식별자로 Traccar 서버에 device를 자동 생성한다.
운영자는 이 PIN과 Rails 서버 주소(adminUrl)만 운전자에게 전달하면 된다.

```
운전자: driver_app 최초 실행 → adminUrl + PIN 입력 → "Register and start"
   └─ POST {adminUrl}/integrations/traccar/register { pin }
        └─ Rails: Bus.find_by(pin:) → 200 { traccarServerUrl, deviceId: bus.traccar_unique_id }
             └─ driver_app: 응답값을 로컬(SharedPreferences)에 저장, 메인 화면으로 전환
                  └─ "운행 시작" 탭 → traccar_client_sdk.start(serverUrl, deviceId)로 GPS 전송 개시
```

운전자는 `traccar_unique_id` 자체를 직접 입력하지 않는다 — Admin이 먼저 발급해둔 값을
PIN 인증으로 대신 받아오는 구조다. `deviceId`는 Traccar 쪽에서 새로 발급되는 게 아니라
**Rails가 Bus 생성 시 이미 만들어 둔 값**을 그대로 내려주는 것뿐이라, 이 시점에 Traccar
서버로의 쓰기(device 생성)는 일어나지 않는다 — 그건 이미 Admin 등록 시점에 끝나 있다.

- 인증 실패(PIN 오류 401, 시도 초과 429, 서버 무응답)는 각각 사람이 읽을 메시지로 변환되어
  `SnackBar`로 노출된다(`driver_app/lib/api_client.dart`).
- `PinCode` 모델과 테이블은 존재하지만 **현재 등록 API의 PIN 인증에는 사용하지 않는다**(레거시) — 실제
  PIN 인증은 `Bus.pin` 컬럼으로 이뤄진다. `has_many :pin_codes` 연관과 `db/seeds.rb`의 데모
  레코드 생성만 남아 있으므로, 새 기능에서 `PinCode`를 참조·확장하지 않는다.

## Rails 수신 측 (구현 완료 — Phase 1)

- **모델**: `buses.traccar_unique_id`(단말 식별자, unique) / `buses.traccar_device_id`(Traccar 내부 device id, 프로비저닝용).
- **엔드포인트**: `POST /integrations/traccar/positions` (`Integrations::TraccarController < ActionController::API`)
  - `X-Ingest-Token` 헤더로 인증(타이밍 안전 비교). 토큰 출처: `credentials[:traccar][:ingest_token]` → `ENV["TRACCAR_INGEST_TOKEN"]` → 개발 기본값 `dev-traccar-token`. 운영에서 미설정 시 **fail-closed**.
  - payload `device.uniqueId` → `Bus` 조회. 그 버스의 **열린 Trip**(없으면 생성)에 `GpsLog`(lat/lng/recorded_at) 적재.
  - 알 수 없는 단말·좌표 누락은 `200`(ack)로 무시 → 포워딩 재시도 폭주 방지.
- 기존 `Trip`/`GpsLog`/`stops#arrival` 로직을 그대로 재사용한다. (시드의 가짜 GPS가 진짜 위치로 대체될 뿐)

### Traccar 포워딩 설정 (`traccar.xml`)

```xml
<entry key='forward.enable'>true</entry>
<entry key='forward.url'>https://<오리진>/integrations/traccar/positions</entry>
<entry key='forward.json'>true</entry>
<entry key='forward.header'>X-Ingest-Token: <비밀토큰></entry>
```

## Admin geofence/group 자동화 (구현 완료 — 노선 배차 연동)

정류장(Stop)을 admin에서 등록하면 Traccar에 geofence(정류장 중심 30m 정사각형)가 자동
생성되고, 버스가 그 정류장의 노선에 배정되는 즉시 geofence 이벤트를 받기 시작한다. 이때
"정류장 geofence ↔ 버스 device"를 하나씩 개별 연결하는 대신, [Traccar
Groups](https://www.traccar.org/permissions-groups/) 기능을 이용해 **노선(Route) 단위로
그룹을 두는 간접 연결** 구조를 쓴다.

```
Route 생성       →  Traccar Group 생성 (route.traccar_group_id)
                    (⚠️ 수정 시는 sync 미호출 — 노선명/운행지역 변경 후 `sync_group` 수동 재동기화로 회복)
Stop 생성/수정    →  Geofence 생성 (stop.traccar_geofence_id) → 소속 Route의 Group에 연결
버스 배차(RouteBus) →  그 Route의 Group에 device 추가 → Group에 연결된 모든 geofence 이벤트 수신 시작
                    (⚠️ Traccar device가 없는 버스는 group sync·device 연결 없이 배차만 저장됨)
배차 해제         →  device를 Group에서 해제 (리소스 삭제 아님 — group·geofence·device 유지)
```

Group에 연결된 geofence 이벤트는 그 Group에 속한 모든 device(및 하위 group)에 자동
전파된다([Traccar Geofences](https://www.traccar.org/geofences/) 문서 참고). 정류장이 늘어날
때마다 그 노선의 버스들을 일일이 재연결할 필요가 없고, 버스를 노선에 새로 배정하면 그 즉시
해당 노선의 모든 정류장 이벤트를 받기 시작한다 — 개별 연결 방식이었다면 정류장 수 ×
버스 수만큼 연결을 관리해야 했을 것을 노선 수만큼으로 줄인 것이다.

이에 맞춰 도메인 모델도 "노선당 버스 1대"에서 **Route-Bus N:N**(`route_buses` join table)으로
전환했다 — 한 노선에 배차 간격 유지를 위해 여러 대가 동시에 배정될 수 있어야 group 설계와
맞는다. 승객 화면 ETA는 배정된 버스들 중 활성 운행 중인 버스가 여럿이면 목표 정류장에 가장
먼저 도착할 버스 하나를 골라 보여준다.

⚠️ **N:N 모델과 Traccar device 단일 group 제약**: Traccar device는 하나의 group에만 속할 수
있어 `TraccarGroupMembership`은 device의 단일 `groupId`를 읽고 쓴다. 모델(`route_buses` N:N)은
한 버스를 여러 노선에 배차하는 것을 막지 않지만, 그러면 나중에 등록한 배차의 group이 기존
group을 덮어쓰고, 한 노선의 배차 해제(`groupId → 0`)가 다른 노선의 배차 연결까지 끊는다
(`set_device_group`은 device 단일 필드 교체 방식 — 다중 group 연결 방식이 아니다). 운영상
제약: **한 버스가 동시에 여러 노선에 배차되는 구성은 현재 지원하지 않는다** — driver_app이
`bus.routes.first`로 첫 노선을 읽는 계약도 이 동일한 "버스당 배차 1개" 가정에 의존한다.
validation(`bus_id uniqueness: scope: route_id`)은 같은 노선 중복 배차만 막고, 버스가 여러
노선에 걸치는 것은 막지 않는다. 배차 단일성 validation 추가와 Traccar 다중 group 연결 방식에
맞춘 membership 재설계는 별도 작업(PR)에서 다룬다.

**정합성 정책 (완전 롤백)**: admin의 Route/Stop/Bus 생성·수정·삭제와 RouteBus 배차 생성·해제는
Traccar API 호출과 하나의 트랜잭션처럼 취급한다. Traccar 쪽 호출이 실패하면 Rails DB 변경도
커밋(생성/수정) 또는 실행(삭제)되지 않는다 — "Traccar 측 선행조건이 없으면 Rails 레코드도 존재할
수 없다"는 원칙이다. 이는 Rails와 Traccar 서버 상태가 서로 어긋나는(레코드는 있는데 실제 Traccar
자원은
없는) 드리프트를 원천적으로 막기 위한 설계로, 대신 Traccar 서버가 다운되어 있으면 **Traccar sync가
필요한** admin 생성·수정·삭제 작업이 실패한다는 트레이드오프를 가진다 — Route 수정과 미프로비저닝
Bus의 RouteBus 배차는 Traccar 호출 없이 진행되므로 별도 예외다. 화면에는 실패 사유(예: Traccar
서버와 통신할 수 없음)를 명확히 표시한다.

이 정합성 원칙의 예외·한계는 `AGENTS.md` "Admin CRUD ↔ Traccar 정합성" 섹션에 상세히 기록되어
있으며, 요점은 다음과 같다. ① 대상별 범위 — Route/Stop/Bus는 생성·수정(transaction+sync)·삭제
(Traccar 먼저, RouteBus는 device group 해제뿐)이고, Bus는 수정 시에도 device sync를 거친다
(삭제는 device 삭제 성공 후 Rails destroy). ② 예외 — Route **수정**은 현재 group sync를 호출하지
않는다; Traccar device가 없는 버스의 배차는 membership 스킵으로 저장된다
(`TraccarGroupMembership.add`의 조기 반환이 group sync보다 앞). ③ 외부 HTTP는 트랜잭션으로
롤백되지 않는다. ④ 양방향 drift — Traccar 쪽에만 남는 orphan(Rails 레코드 소실 → Traccar 콘솔
수동 정리)과, 삭제 시 Rails `destroy` 실패로 Rails 레코드만 남는 반대 방향 drift가 모두 가능하다.
⑤ 복구 — Rails 레코드가 남아 있으면 admin 수동 sync 액션(`sync_group`/`sync_geofence`/
`sync_device`; id가 남아 있으면 먼저 콘솔에서 `traccar_*_id`를 nil로 리셋)으로 단일 리소스를
재생성한다. 단, **연관 링크는 자동 복구되지 않는다** — group 재생성 후 각 Stop geofence의 group
permission은 `sync_geofence` 재실행으로 복원하고, device 재생성 후 배차 membership는 수동 sync
액션이 없으므로 admin에서 배차 해제→재배차로 재연결하거나 콘솔 수동 작업이 필요하다.

## 운영 측 (운영자가 수행)

- **Traccar 서버**: Docker(`traccar/traccar`)로 기동, 데이터 볼륨 + `traccar.xml` 영속화. 포트 8082(API/WS), 5055(OsmAnd 수신).
- **차량 ↔ 단말 등록**: Admin에서 차량을 등록하면 `traccar_unique_id`가 자동 발급되고
  `TraccarDeviceSync`가 같은 값으로 Traccar 서버에 device를 자동 생성해 `bus.traccar_device_id`에
  저장한다(수동 등록 불필요, [운전자 온보딩](#운전자-온보딩-driver_app-구현-완료--e2e-검증됨) 참고).
  운영자는 이 서버 주소와 PIN만 운전자에게 전달하면 된다.

## 보안

- 수신 엔드포인트: 공유 토큰 헤더 필수(+가능하면 Traccar 호스트 IP 제한·rate limit).
- `traccar_unique_id`는 추측 불가능해야 함 — OsmAnd는 id만 알면 위치 주입 가능하므로 스푸핑 방지의 핵심.
- 수신 컨트롤러의 `ingest_token`(및 `server_url`)은 Rails credentials → ENV
  (`TRACCAR_INGEST_TOKEN` 등) → 개발 기본값 순서로 관리(커밋 금지). Traccar API 매니저 자격증명
  (`TraccarApiClient`의 `api_base_url`/`api_email`/`api_password`)은 **credentials만** 읽는다 —
  ENV fallback은 구현돼 있지 않다(커밋 금지).

## 단계별 로드맵

로컬 Rails 서버에 `driver_app`을 연결해 Traccar 없이 GPS 수신 계약을 시험하는 방법은
[driver_app과 로컬 Rails 서버 연결 테스트](driver-app-local-rails-test.md)를 참고한다.

| 단계 | 내용 | 상태 |
|---|---|---|
| 0 | Traccar Docker 기동 + 위치 수신 확인 | 운영 수동 |
| 1 | Rails 수신 엔드포인트 + 모델 컬럼 + 포워딩 → GpsLog 적재 | **완료** |
| 1.5 | Admin 정류장 등록 시 geofence 자동 생성 + 노선 단위 group 자동 연결(배차 시 device 자동 추가) | **완료** |
| 2 | 차량 등록 시 Traccar 디바이스 자동 프로비저닝(REST API) + admin 단말 상태 표시 | **완료** |
| 2.5 | driver_app 온보딩(PIN → register API → deviceId 수신 → traccar_client_sdk 시작) 실제 서버 e2e 검증 | **완료** |
| 3 | Trip 자동 종료(오프라인/타임아웃, Solid Queue) | 예정 |

> 폴링 유지·지도 미도입 결정에 따라, 실시간 Cable·지도 단계는 로드맵에서 제외.
