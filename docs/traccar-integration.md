# Traccar 위치 추적 연동 설계

오픈소스 GPS 추적 서버 [Traccar](https://www.traccar.org/)로 버스 위치를 수집하고, 기존 시민 서비스의 도착정보(ETA·진행바)에 반영한다.

## 결정 사항 (MVP)

1. **운전자 단말**: 공식 **Traccar Client 앱**을 그대로 사용 — 커스텀 iOS 앱 미개발.
2. **실시간 방식**: 기존 **폴링 유지**(`arrival_polling_controller.js`, 5초). Solid Cable 도입은 보류.
3. **지도**: 시민 화면은 **진행바만 유지**. 별도 지도 없음.

## 데이터 흐름

```
운전자 폰 (Traccar Client, OsmAnd :5055)
   └─ GPS(id·lat·lon) ─▶ Traccar 서버 (Docker, API :8082)
                              └─ 위치 포워딩(JSON POST) ─▶ Rails  POST /integrations/traccar/positions
                                                              └─ Bus 매핑 → Trip → GpsLog 적재
                                                                    └─ 기존 stops#arrival(폴링)이 읽어 시민 웹에 표시
```

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
Route 생성/수정   →  Traccar Group 생성 (route.traccar_group_id)
Stop 생성/수정    →  Geofence 생성 (stop.traccar_geofence_id) → 소속 Route의 Group에 연결
버스 배차(RouteBus) →  그 Route의 Group에 device 추가 → Group에 연결된 모든 geofence 이벤트 수신 시작
배차 해제         →  Group에서 device 제거
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

**정합성 정책 (완전 롤백)**: admin의 Route/Stop/RouteBus 생성·수정·삭제는 Traccar API 호출과
하나의 트랜잭션처럼 취급한다. Traccar 쪽 호출이 실패하면 Rails DB 변경도 커밋(생성/수정) 또는
실행(삭제)되지 않는다 — "Traccar 측 선행조건이 없으면 Rails 레코드도 존재할 수 없다"는
원칙이다. 이는 Rails와 Traccar 서버 상태가 서로 어긋나는(레코드는 있는데 실제 Traccar 자원은
없는) 드리프트를 원천적으로 막기 위한 설계로, 대신 Traccar 서버가 다운되어 있으면 admin에서
해당 CRUD를 전혀 수행할 수 없다는 트레이드오프를 가진다. 화면에는 실패 사유(예: Traccar
서버와 통신할 수 없음)를 명확히 표시한다.

## 운영 측 (운영자가 수행 — 미구현/수동)

- **Traccar 서버**: Docker(`traccar/traccar`)로 기동, 데이터 볼륨 + `traccar.xml` 영속화. 포트 8082(API/WS), 5055(OsmAnd 수신).
- **차량 ↔ 단말 등록**: 각 버스에 추측 불가능한 `traccar_unique_id` 발급(예: `goseong-1-a8f3c2`). Admin에서 차량 등록 시 `TraccarDeviceSync`가 이 값으로 Traccar 서버에 디바이스를 자동 생성해 `bus.traccar_device_id`에 저장(수동 등록 불필요). 운전자는 Traccar Client에 서버 주소 + 이 식별자 입력 후 "시작".
- **PIN 흐름**: 기존 `PinCode`는 운영자가 운전자에게 단말 식별자를 발급/승인하는 본인확인 용도로 유지.

## 보안

- 수신 엔드포인트: 공유 토큰 헤더 필수(+가능하면 Traccar 호스트 IP 제한·rate limit).
- `traccar_unique_id`는 추측 불가능해야 함 — OsmAnd는 id만 알면 위치 주입 가능하므로 스푸핑 방지의 핵심.
- Traccar 매니저 자격증명·ingest 토큰은 Rails credentials/ENV로 관리(커밋 금지).

## 단계별 로드맵

| 단계 | 내용 | 상태 |
|---|---|---|
| 0 | Traccar Docker 기동 + Traccar Client로 위치 수신 확인 | 운영 수동 |
| 1 | Rails 수신 엔드포인트 + 모델 컬럼 + 포워딩 → GpsLog 적재 | **완료** |
| 1.5 | Admin 정류장 등록 시 geofence 자동 생성 + 노선 단위 group 자동 연결(배차 시 device 자동 추가) | **완료** |
| 2 | 차량 등록 시 Traccar 디바이스 자동 프로비저닝(REST API) + admin 단말 상태 표시 | **완료** |
| 3 | Trip 자동 종료(오프라인/타임아웃, Solid Queue) | 예정 |

> 폴링 유지·지도 미도입 결정에 따라, 실시간 Cable·지도 단계는 로드맵에서 제외.
