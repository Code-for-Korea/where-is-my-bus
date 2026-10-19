# 로컬버스 멀티테넌트 실시간 버스 위치 서비스 기획서

- 문서 버전: v0.1
- 작성일: 2026-10-17
- 참고 프로젝트: https://github.com/Code-for-Korea/where-is-my-bus
- 상태: 기획 초안 (저장소 세부 구현 및 현장 환경 검증 필요)

## 0. 결정 사항 반영 (2026-10-18)

datalogger 분석에서 소유자 결정이 확정되어 본 문서에 반영했다. 전체 결정 목록은 `.omo/notepads/datalogger-analysis/decisions.md` 참고.

- **멀티테넌트 보류, 단일 소규모 서버 운영**: 테넌트 격리·독립 도메인·서브도메인 스킴·멤버십 기반 역할은 이번 계획에서 제외한다. 관리자(admin)·승객(service)·GPS 수신기(integrations)를 소규모 서버 1대에서 함께 실행한다. 본 문서의 테넌트 관련 절(4.1 등)은 삭제하지 않고 향후 재검토 대상으로 보존한다.
- **위치 이력 보존 확정**: 원본 24시간 + StopEvent 7일 + 집계 통계 90일. 30초 샘플링은 후속 측정 후 검토.
- **OsmAnd 타임스탬프**: 현행 ISO8601 문자열 파싱 유지. 숫자 타임스탬프(초/밀리초) 지원은 실기기 샘플 확보 후 추가.
- **운전자 앱**: 현행 Flutter + Traccar Client SDK + PIN 1회용 인증 유지.
- **초기 규모·SLO**: 동시 접속 100명, 가용성 99%, p95 응답 500ms. 운영 실측에 따라 조정.
- **폴링**: 근접 가변 폴링(3정류장 이상 10초, 2정류장 5초, 1정류장 이하 3초 — 2026-10-19 결정), SSE 전환 보류.
- **지도 SDK**: Google Maps·Kakao Map·OpenStreetMap을 동시 지원(우선순위가 아닌 멀티 벤더 구성, 2026-10-19 Naver 제외).
- **버스 표시**: `RouteBusSelector` 확장 — 승객 화면은 단일 추천 버스, 관리자·지도 화면에서만 다중 버스 표시.
- **unknown-device 200-ack 계약 유지** 및 **CurrentPosition 테이블 신설** 확정.
- **P0 실행 범위 확정**: 단일 서버·테넌트 없음. 10개 P0 작업 목록은 `docs/datalogger-development-plan.md`의 "0.5. P0 실행 범위 (2026-10-18 확정)" 섹션 및 `.omo/plans/datalogger-p0-execution.md` 참고.

## 1. 목적

기존 로컬버스 프로젝트를 기반으로 여러 지자체가 독립적인 브랜드와 계정으로 버스 위치 서비스를 제공하도록 확장한다. Java 기반 Traccar 서버의 핵심 GPS 수집 기능을 Rails로 대체하여 1 vCPU / 1GB RAM 수준의 소형 서버에서도 운영 가능한 구성을 실험한다. 운전자의 기존 Traccar Client를 가능한 한 유지한다.

## 2. 서비스 범위와 가정

- 전체 등록 버스: 약 100대.
- 노선: 우선 10개. 노선당 운행 차량 최대 5대라면 동시 운행 차량은 최대 50대. 100대 동시 운행은 별도 상한 시나리오로 시험.
- GPS 전송 간격: 기본 10초. 30초는 저부하 비교 시나리오. 정차·운행 종료 시 가변 주기는 클라이언트 지원 여부 확인 후 결정.
- 지자체: **멀티테넌트는 보류(2026-10-18 결정)**. 단일 소규모 서버에서 관리자·승객·GPS 수신기를 함께 운영하며, 테넌트 격리는 향후 별도 검토 대상.
- 지자체별 서비스 주소: 서브도메인·독립 도메인 스킴은 테넌트 보류에 따라 이번 범위에서 제외.
- 운전자: Traccar Client의 OsmAnd HTTP 방식과 호환되는 수신 API 사용. 실제 버전별 요청 샘플로 검증.
- GPS 이력: **원본 24시간 + StopEvent 7일 + 집계 통계 90일 보존(확정)**. 30초 간격 샘플링은 후속 측정 후 검토. 최신 위치는 CurrentPosition 테이블로 관리.
- 서비스 화면: 관리자 페이지, 노선별 승객 지도, 버스 위치·운행 상태, 정류장 도착 정보.

## 3. 사용자와 역할

| 역할 | 주요 권한 |
| --- | --- |
| 플랫폼 관리자 | 테넌트 개설, 도메인 승인, 시스템 상태 확인 |
| 지자체 관리자 | 자기 테넌트의 노선·정류장·차량·사용자 관리 |
| 운영 담당자 | 차량 배차, 운행 상태, GPS 연결 확인 |
| 열람 담당자 | 자기 테넌트 운영 현황 조회 |
| 운전자 | 등록된 장치로 위치 송신 |
| 승객 | 로그인 없이 해당 지자체의 노선·정류장·실시간 버스 위치 조회 |

## 4. 핵심 기능

### 4.1 테넌트 및 독립 사이트 (보류 — 향후 재검토)

> **2026-10-18 결정:** 멀티테넌트 작업은 이번 계획에서 보류한다. 아래 항목은 단일 테넌트 운영 시 불필요하므로 구현하지 않으며, 다중 지자체 확장 시 본 절을 다시 검토한다.

- 테넌트 개설 시 기본 주소(`a.localbus.example`) 발급.
- 지자체 소유 독립 주소(`bus.example.go.kr`) 연결 지원: 소유권 확인, DNS 설정, TLS 인증서 준비 후 활성화.
- 대표 도메인 지정 및 비대표 도메인 리디렉션. 기본 주소는 QR코드 호환을 위해 유지.
- 테넌트별 로고, 사이트명, 색상, 안내 문구, 노선/정류장 데이터 설정.
- 한 사용자가 여러 테넌트에 다른 역할로 소속될 수 있도록 멤버십 모델 적용.

### 4.2 GPS 수집과 차량 위치

- Traccar Client가 보내는 OsmAnd 호환 GET/POST 요청 수신. **P0에서는 Traccar 포워딩을 주 경로로 유지하면서 신규 OsmAnd `/gps` 엔드포인트(GET/POST)를 그림자 경로로 추가한다(2026-10-18 확정)** — 운전자 앱 변경 없이 점진 전환이 가능하다. 두 경로 모두 공통 PositionIngestor 서비스를 거쳐 CurrentPosition/PositionHistory/GpsLog/Trip/StopEvent에 적재된다.
- 장치 식별, 인증, 위치 유효성, 측정 시각 및 지연 전송 검증. P0에서는 기존 토큰 인증을 유지하고, Device 테이블 스키마만 추가하며 per-device 인증 로직은 P1로 미룬다.
- 최신 위치는 차량별 1건 유지. **CurrentPosition 테이블 신설로 확정(2026-10-18)** — 차량당 1행 직접 조회하며, recorded_at이 역전된 재전송이 최신 위치를 덮어쓰지 않도록 upsert 시각 역전 방지를 둔다. 이력은 **PositionHistory 24시간, StopEvent 7일, 집계 통계(RouteSegmentStat) 90일 보존 후 자동 삭제(확정)**.
- 정류장 접근/도착/이탈 이벤트 판정 및 중복 방지(dedup_key). P0에서 Rails 측 StopEvent 판정 서비스로 구현한다. 좌표 없는 정류장(`Stop#coordinates?` false)은 판정에서 스킵한다.
- 운행 종료 신호가 없는 trip(오프라인/타임아웃)은 Solid Queue recurring 잡으로 자동 종료해 GpsLog 무한 누적을 막는다.
- 위치 정보 수신 지연·연결 끊김 표시.
- **unknown-device 200-ack 계약 유지(2026-10-18 확정)**: 인증 실패만 401, 그 외(알 수 없는 단말·좌표 누락)는 200 ack로 무시한다. 4xx 반환 시 Traccar 포워딩 재시도 폭주를 피하기 위함.

### 4.3 승객 서비스

- 지도 위 노선, 정류장, 차량별 실시간 위치 표시.
- **지도 SDK는 Google Maps·Kakao Map·OpenStreetMap을 동시 지원(2026-10-18 결정, 2026-10-19 Naver 제외·OSM 추가)**. 우선순위가 아닌 멀티 벤더 구성으로, 지자체·브랜딩·라이선스 조건에 따라 런타임 또는 설정에서 선택한다. **P0 구현: Google Maps·Kakao는 실제 SDK 연동, OpenStreetMap은 Leaflet + OSM 타일(키 불필요).**
- **승객 화면에는 노선별 단일 추천 버스를 표시한다(2026-10-18 결정)**. 기존 `RouteBusSelector`를 확장해 추천 로직을 공유하고, 다중 버스 표시는 관리자·지도 화면에서만 제공한다. 운행 방향 및 최신 수신 시각 제공.
- **폴링은 근접 가변으로 유지한다. SSE 전환은 보류(2026-10-18 결정, 2026-10-19 가변 폴링으로 구체화)** — 단일 서버에서 SSE 커넥션 관리 부담이 크다. 정류장 도착 임박 신호의 신선도가 중요해 3정류장 이상 10초, 2정류장 5초, 1정류장 이하 3초로 조정한다(평균 요청 수는 10초 고정과 유사).
- 지도 아이콘은 위치 보간 애니메이션을 사용할 수 있으나 예측 위치와 실제 수신 위치를 혼동하지 않도록 처리.
- 정류장 QR코드와 도착 예정 정보 제공. ETA 정확도는 별도 검증.

### 4.4 관리자

- 테넌트별 차량·GPS 장치·노선·정류장·운행 관리.
- 장치 마지막 수신 시각, 오류율, 배차 상태, 최근 도착 이벤트 조회.
- 플랫폼 관리자와 지자체 관리자의 데이터 접근 권한 분리.

> **2026-10-18 결정:** 멀티테넌트 보류에 따라 테넌트별 권한 분리는 이번 범위에서 제외한다. 기존 `member`/`operator` 역할 구조를 유지한다.

## 5. 운영 원칙

1. 기존 `where-is-my-bus` Rails 코드베이스를 우선 확장한다. 별도 GPS 마이크로서비스는 필수로 만들지 않는다.
2. 초기 DB는 SQLite(WAL)로 시작한다. 실제 쓰기 경합과 운영 지표를 측정한 뒤 MySQL/PostgreSQL 전환을 판단한다.
3. 1 vCPU / 1GB는 검증 목표 사양이지 보장 사양이 아니다. 메모리 부족 시 2GB 이상으로 상향한다.
4. Traccar와 새 수신기를 병행 비교한 뒤 단계적으로 전환한다. 앱 설정만 변경하면 되는지 실기기에서 검증한다.
5. GPS 장치 ID만으로 신뢰하지 않는다. TLS, 장치별 비밀값 또는 호환 가능한 인증 수단, 요청 제한을 적용한다.
6. 위치 정보의 수집 목적, 보존 기간, 관리자 열람 범위, 개인정보 처리 안내를 문서화한다.

## 6. 초기 트래픽 추정

| 시나리오 | 동시 운행 | 전송 간격 | 평균 GPS 요청/초 | 12시간 요청 수 |
| --- | ---: | ---: | ---: | ---: |
| 기본 | 50대 | 10초 | 5 | 216,000 |
| 저부하 | 50대 | 30초 | 약 1.67 | 72,000 |
| 상한 | 100대 | 10초 | 10 | 432,000 |

승객 트래픽은 별도다. **초기 목표는 동시 접속 100명(2026-10-18 결정)**이며, 10초 폴링 기준 약 10 req/s가 추가된다. 가용성 99%, p95 응답 500ms를 초기 목표로 하고, 운영 실측 후 1,000명(약 100 req/s) 시나리오를 재검토한다. 노선별 응답 캐시와 부하 시험이 필요하다.

## 7. 비기능 요구사항과 성공 기준

- 테넌트 간 데이터 노출이 없어야 한다(자동 테스트 필수). (멀티테넌트 보류 결정에 따라 단일 테넌트 운영 중에는 해당 없음, 확장 시 재검토)
- GPS 측정 시각이 역전되거나 오래된 재전송이 와도 최신 위치가 뒤로 돌아가지 않아야 한다.
- 24시간 연속 부하 시험에서 OOM 종료, SQLite 잠금 오류, 위치 누락이 발생하지 않는 것을 목표로 한다.
- GPS 수신 p95 200ms 이내, 관리자 주요 화면 p95 1초 이내를 초기 시험 목표로 설정한다(보장값 아님).
- **승객 서비스 초기 SLO(2026-10-18 결정): 동시 접속 100명, 가용성 99%, p95 응답 500ms.** 운영 측정에 따라 조정한다.
- SQLite 파일·WAL을 포함한 일관성 있는 백업 및 복구 절차를 마련한다.
- 독립 도메인 연결 전 DNS·TLS 검증을 완료한다. (테넌트 보류 결정에 따라 단일 도메인 운영 중에는 해당 없음)

## 8. 범위 밖 / 후속 과제

- Traccar 전체 단말 프로토콜과 차량 관제 기능 재구현.
- 모든 지자체에 전용 서버·DB 제공.
- 장기 GPS 원본 이력 분석.
- Roundhouse + Spinel의 전체 Rails 앱 네이티브 컴파일: 별도 기술 실험으로 분리.
- 고정밀 도착 예측 알고리즘, 복잡한 Map Matching은 초기 MVP 이후 개선.

## 9. 결정할 사항

2026-10-18 기준으로 아래 항목이 확정됐다. 전체 근거는 `.omo/notepads/datalogger-analysis/decisions.md` 참고.

- 지자체 수와 지자체별 차량·노선 상한. (멀티테넌트 보류 — 단일 테넌트 운영 중에는 보류)
- 실제 운전자 앱 버전과 Traccar Client 전송 파라미터·인증 방식. **확정: 현행 Flutter + Traccar Client SDK + PIN 1회용 인증 유지.** 전송 파라미터 세부는 실기기 샘플 확보 후 확정.
- 24시간 원본 이력 전체 저장 또는 30초 샘플링 선택. **확정: 원본 24시간 + StopEvent 7일 + 집계 통계 90일.** 30초 샘플링은 후속 측정 후 검토.
- 독립 도메인 TLS 자동화 방식(프록시 직접 관리 또는 Cloudflare for SaaS 등). (테넌트 보류 결정에 따라 보류)
- 승객 동시 접속 목표 및 서비스 가용성 목표. **확정: 동시 100명, 가용성 99%, p95 응답 500ms.** 운영 실측에 따라 변경 가능.
- P0 실행 범위. **확정(2026-10-18): 단일 서버·테넌트 없음.** 1GB 기준선 측정, OsmAnd 샘플 수집, 5개 테이블 마이그레이션, 공통 PositionIngestor, `/gps` 엔드포인트, StopEvent 판정, Trip 자동 종료, 보존 잡, 멀티 벤더 지도 UI, 테스트·문서의 10개 작업으로 구성된다. 실행 계획은 `.omo/plans/datalogger-p0-execution.md` 참고.

## 10. P0 구현 결과 (2026-10-18)

P0 작업이 `.omo/plans/datalogger-p0-execution.md`에 따라 완료됐다. 주요 산출물과 검증 결과는 아래와 같다.

### 10.1 데이터 모델

| 테이블 | 목적 | 핵심 제약 |
| --- | --- | --- |
| `current_positions` | 차량별 최신 위치 1건 | `bus_id` unique FK, lat/lng NOT NULL, recorded_at/received_at |
| `position_histories` | 원본 위치 이력(24h 보존) | `bus_id` FK, `[bus_id, recorded_at]` 인덱스, telemetry 필드 |
| `stop_events` | 정류장 접근/도착/이탈 이벤트(7d 보존) | `dedup_key` unique, bus_id/stop_id/event_type/occurred_at |
| `route_segment_stats` | 구간별 평균 소요 시간 집계(90d 보존) | 복합 unique `[route_id, from_stop_id, to_stop_id, hour_of_day, date]` |
| `devices` | 장치 스키마(P0 인증 미사용) | `bus_id` unique FK, `unique_id` unique, credential_digest |

### 10.2 API 경로

| 경로 | 메서드 | 설명 |
| --- | --- | --- |
| `POST /integrations/traccar/positions` | Traccar 포워딩 수신 | `X-Ingest-Token` 인증, unknown device/누락 좌표 시 200 ack |
| `GET/POST /gps` | OsmAnd 호환 수신 | id/lat/lon/timestamp/speed/bearing/battery/accuracy, ISO8601 timestamp, 숫자 타임스탬프 501 |
| `GET /routes/:id/map` | 노선 지도 페이지 | Google Maps 우선, Kakao 실연동, OSM(Leaflet) |
| `GET /r/:region_slug/:stop_id/arrival` | 승객 도착 정보 JSON | 10초 폴리ng 대상 |

### 10.3 보존 정책

`config/initializers/datalogger.rb`에서 중앙 관리하며 `RetentionJob`이 매 시간 30분에 실행한다(`config/recurring.yml`, Solid Queue recurring — production 환경).

- `PositionHistory`: 24시간 초과 삭제
- `GpsLog`: 24시간 초과 삭제
- `StopEvent`: 7일 초과 삭제
- `RouteSegmentStat`: 90일 초과 삭제

### 10.4 지도 SDK 설정

- `MAP_PROVIDER` 환경 변수(`google`/`kakao`/`osm`)로 공급자 선택. 기본값 `google`.
- 지도 제공자·API 키는 **관리자 화면(/admin/setting)에서 설정**(2026-10-19 결정) — settings 테이블이 단일 소스로, `MAP_PROVIDER` ENV·크리덴셜 조회를 대체한다. Google Maps 키 미설정 시 폴백 메시지 출력.
- Kakao는 실제 SDK를 연동(관리자 화면에서 앱 키 입력). OpenStreetMap은 Leaflet + OSM 타일로 키 없이 동작. Naver는 2026-10-19 제외(라이선스·발급 절차 부담) — 필요 시 MapProvider 인터페이스로 재추가.

### 10.5 검증

- `bin/rails test`: 113 tests, 339 assertions, 0 failures, 0 errors, 0 skips (2026-10-18)
- `bin/rubocop`: 122 files inspected, no offenses
- P0 가드레일 준수: `tenant_id` 미도입, Device 인증 로직 미추가, SSE/WebSocket 미도입, 10초 폴리ng 유지
- 작업별 산출물·검증 근거는 `.omo/evidence/task-1-datalogger-p0-execution.md` ~ `task-9-datalogger-p0-execution.md` 참고. CI에 테스트 잡이 없으므로 테스트 통과는 로컬 실행으로 검증했다.
