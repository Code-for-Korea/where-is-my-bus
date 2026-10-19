# 로컬버스 멀티테넌트·경량 GPS 서버 개발 계획서

- 문서 버전: v0.1
- 작성일: 2026-10-17
- 대상 저장소: https://github.com/Code-for-Korea/where-is-my-bus
- 원칙: 기존 구현을 먼저 조사하고, 실제 모델/라우트/DB 구성에 맞춰 적용한다. 아래 경로와 모델은 제안안이다.

## 0. 결정 사항 반영 (2026-10-18)

datalogger 분석에서 소유자 결정이 확정되어 본 문서에 반영했다. 전체 결정 목록은 `.omo/notepads/datalogger-analysis/decisions.md` 참고.

- **멀티테넌트 보류, 단일 소규모 서버 운영**: Tenant/TenantDomain/Membership, 서브도메인·독립 도메인, tenant_id 스킴은 이번 계획에서 제외한다. 관리자·승객·GPS 수신기를 소규모 서버 1대에서 함께 실행한다. 관련 단계(1·2단계)는 삭제하지 않고 보류로 표기한다.
- **위치 이력 보존 확정**: PositionHistory(원본) 24시간 + StopEvent 7일 + 집계 통계 90일. 30초 샘플링은 후속 측정 후 검토.
- **OsmAnd 타임스탬프**: 현행 ISO8601 문자열 파싱 유지. 숫자 타임스탬프(초/밀리초) 지원은 실기기 샘플 확보 후 추가.
- **운전자 앱**: 현행 Flutter + Traccar Client SDK + PIN 1회용 인증 유지.
- **초기 규모·SLO**: 동시 접속 100명, 가용성 99%, p95 응답 500ms. 운영 실측에 따라 조정.
- **폴링**: 10초 폴링 유지, SSE 전환 보류.
- **지도 SDK**: Google Maps·Kakao Map·Naver Map을 동시 지원(우선순위가 아닌 멀티 벤더 구성).
- **버스 표시**: `RouteBusSelector` 확장 — 승객 화면은 단일 추천 버스, 관리자·지도 화면에서만 다중 버스 표시.
- **unknown-device 200-ack 계약 유지** 및 **CurrentPosition 테이블 신설** 확정.

## 0.5. P0 실행 범위 (2026-10-18 확정)

멀티테넌트 보류 결정에 따라 P0는 **단일 서버·테넌트 없음** 범위로 확정됐다. 1GB 단일 서버에서 관리자·승객 서비스·GPS 수신이 동봉 실행되는 전제이며, 실행 계획 전문은 `.omo/plans/datalogger-p0-execution.md`, 소유자 결정 근거는 `.omo/notepads/datalogger-analysis/decisions.md` 참고.

P0는 아래 10개 작업으로 구성된다. 실행 순서는 의존 관계에 따라 6개 웨이브(기준선·샘플 → 데이터 모델·공통 수신 → 수신기·이벤트 → 정리·보존 → UI → 마무리)로 나뉜다.

| # | 작업 | 닫는 갭 |
| --- | --- | --- |
| 1 | 1GB 단일 서버 기준선 측정(부팅/유휴/부하 RSS, SQLite 잠금, 보고서 `.omo/evidence/task-1-datalogger-p0-execution.md`) | GAP-1, GAP-11, GAP-12 |
| 2 | OsmAnd 요청 샘플 수집 및 명세화(`docs/osmand-request-samples.md`, 실기기 샘플 기반) | GAP-2 |
| 3 | CurrentPosition/PositionHistory/StopEvent/RouteSegmentStat/Device 마이그레이션(`tenant_id` 없음) | GAP-3 |
| 4 | 공통 PositionIngestor 서비스 + Traccar 포워딩 연동 리팩터링 | GAP-4 |
| 5 | OsmAnd `/gps` 엔드포인트(GET/POST, ISO8601 파싱, 200-ack 계약) | GAP-5 |
| 6 | StopEvent 판정 서비스(접근/도착/이탈, 히스테리시스, dedup_key) | GAP-6 |
| 7 | Trip 자동 종료 잡(마지막 GPS 수신 후 타임아웃, Solid Queue recurring) | GAP-7 |
| 8 | 보존/삭제 잡(PositionHistory 24시간, StopEvent 7일, RouteSegmentStat 90일, 소규모 배치 삭제) | GAP-8 |
| 9 | 멀티 벤더 지도 UI + `RouteBusSelector` 확장(Google Maps 우선, Kakao/Naver 공통 인터페이스 + stub) | GAP-9, GAP-10 |
| 10 | 테스트 보강 및 docs 업데이트 | IS-1~IS-12 문서화 |

**P0에서 하지 않는 것(가드레일):** 멀티테넌트·독립 도메인·서브도메인 격리, Traccar 완전 대체와 운전자 앱 Traccar Client SDK 제거, SSE/WebSocket, 30초 GPS 샘플링, 숫자 타임스탬프 지원, per-device 인증(Device 스키마만 추가하고 인증 로직은 P1), Roundhouse/Spinel PoC, 앱스토어 배포 파이프라인.

**주요 아키텍처 결정:** Traccar 포워딩을 주 경로로 유지하면서 새 `/gps` 엔드포인트를 그림자 경로로 추가해 운전자 앱 변경 없이 점진 전환한다. 두 경로 모두 공통 PositionIngestor로 CurrentPosition/PositionHistory/GpsLog/Trip/StopEvent에 적재한다. CurrentPosition은 차량당 1행 upsert이며 recorded_at 역전 재전송이 최신 위치를 덮어쓰지 않는다. 지도는 Google Maps를 먼저 구현하고 Kakao/Naver는 공통 MapProvider 인터페이스로 준비한다.

## 1. 기술 방향

- 애플리케이션: 기존 Rails 8 기반 코드베이스를 우선 유지.
- 데이터 저장: SQLite + WAL, 단일 서버 로컬 영구 디스크.
- 웹서버: Puma 단일 프로세스(워커 0)와 소수 스레드로 시작.
- GPS: Traccar Client OsmAnd 호환 HTTP 수신기.
- 백그라운드 처리: 기존 Solid Queue가 있다면 사용하되 1GB RAM에서 별도 프로세스 메모리 검증. 단순 정리 작업은 주기 실행 대안 검토.
- 지도: **Google Maps·Kakao Map·Naver Map을 동시 지원하는 멀티 벤더 구성(2026-10-18 결정)**. 지자체·라이선스 조건에 따라 런타임 또는 설정에서 선택. 노선별 최신 위치 API 제공.
- 멀티테넌트: 공유 DB + `tenant_id`, 도메인 기반 테넌트 판별. **보류(2026-10-18 결정)** — 단일 테넌트로 운영하며 tenant_id 스킴은 향후 별도 검토.
- Roundhouse + Spinel: GPS 수집 기능을 분리 가능한 형태로 만든 뒤 별도 PoC 진행. DB 드라이버, Rails 호환성, 실메모리 이점은 검증 전제.

## 2. 선행 조사

1. 저장소의 실제 Rails 버전, Gemfile, DB 설정, Puma, Solid Queue, Kamal 구성 확인.
2. `/admin`, 승객 페이지, Flutter 운전자 앱의 현행 구현 확인.
3. Traccar REST API, Webhook, Geofence, 위치 데이터 저장 관련 코드와 호출 경로 추적.
4. Traccar Client 실기기 요청 샘플(GET/POST, 파라미터, 타임스탬프 단위, 응답 기대값, 인증) 수집.
5. 현행 Rails 부팅 RSS, 유휴 RSS, GPS 수신 부하, 승객 조회 부하 측정.

## 3. 목표 아키텍처

```text
기본 서브도메인 / 지자체 독립 도메인
                 |
         Reverse Proxy / TLS
                 |
       기존 Rails 애플리케이션
         |       |        |
     관리자    승객 API   GPS 수신 API
         |       |        |
      Tenant / Route / Bus / Device
                 |
       SQLite WAL (영구 볼륨)
                 |
     최신 위치 / 단기 이력 / 이벤트

Traccar Client -> 공통 GPS 수신 호스트 -> 장치 인증 -> Tenant/Bus
```

GPS 수신 호스트는 일반 승객 사이트의 Host 기반 테넌트 식별에 의존하지 않고, 인증된 장치 매핑으로 테넌트를 결정한다.

> **2026-10-18 결정:** 서브도메인·독립 도메인·Tenant 계층은 보류다. 단일 도메인에서 관리자·승객·GPS 수신기를 함께 실행하며, 위 다이어그램의 Tenant 부분은 다중 지자체 확장 시 참고용으로 보존한다.

## 4. 데이터 모델 변경안

> **2026-10-18 결정:** 멀티테넌트 보류에 따라 Tenant·TenantDomain·Membership 모델과 `tenant_id` 컬럼은 이번 범위에서 제외한다. **CurrentPosition 테이블 신설은 확정(OD 17)** — 차량당 1행 직접 조회가 `Trip`+`GpsLog` 파생보다 단순하고 빠르다. 아래 표는 다중 지자체 확장 시 참고용으로 보존한다.

| 모델 | 주요 컬럼 / 제약 |
| --- | --- |
| Tenant | name, slug(고유), status, settings |
| TenantDomain | tenant_id, hostname(전체 고유), kind, primary, verified_at, activated_at |
| Membership | user_id, tenant_id, role; 사용자·테넌트 조합 고유 |
| Route / Stop / Bus | tenant_id, 기존 컬럼 유지 |
| Device | tenant_id, bus_id, unique_id(전체 고유), credential_digest, last_seen_at |
| CurrentPosition | tenant_id, bus_id(고유), lat, lon, speed, bearing, recorded_at, received_at |
| PositionHistory | tenant_id, device_id, lat, lon, recorded_at, received_at |
| StopEvent | tenant_id, bus_id, stop_id, event_type, occurred_at, dedup_key |

기존 모델 이름이 다르면 새로 중복 생성하지 않고 현행 모델을 확장한다. 외래키와 복합 유일성 제약으로 교차 테넌트 연결을 방지한다.

## 5. 단계별 구현

### 0단계. 현행 시스템 기준선 확보

- 기존 기능·데이터 모델·배포 방식 문서화.
- Traccar 이벤트와 실제 GPS 요청 샘플 수집.
- CPU/RAM/SQLite 잠금/응답 시간 계측 도구 준비.
- 테스트 데이터: 10개 노선, 노선당 5대, 등록 100대.

**완료 기준:** 변경 전 시스템의 GPS·관리자·승객 동작과 자원 사용량을 재현할 수 있다.

### 1단계. 멀티테넌트 기반 (보류 — 2026-10-18 결정)

> 멀티테넌트 보류에 따라 이번 계획에서 실행하지 않는다. 다중 지자체 확장 시 아래 항목을 그대로 검토한다.

- Tenant, TenantDomain, Membership 도입.
- 기존 데이터는 기본 테넌트로 마이그레이션하고 롤백 절차 작성.
- 요청 Host를 검증된 TenantDomain에 매핑.
- 플랫폼 관리자와 테넌트 관리자의 권한 분리.
- Route/Bus/Stop/Device 및 조회 API의 tenant_id 범위 강제.
- 캐시 키·잡 인자·로그·파일 저장 경로의 테넌트 분리.

**완료 기준:** A 테넌트 관리자가 B 테넌트의 리소스를 URL 조작, API 호출, 연관 ID 변경으로 열람·수정할 수 없다.

### 2단계. 기본 서브도메인 및 독립 도메인 (보류 — 2026-10-18 결정)

> 멀티테넌트 보류에 따라 이번 계획에서 실행하지 않는다. 단일 도메인으로 운영한다.

- 기본 서브도메인 자동 생성, 충돌 및 예약어 검사.
- 사용자 정의 도메인 등록 → 소유권 확인 → DNS 연결 확인 → TLS 인증서 준비 → 활성화.
- 대표 도메인/리디렉션 정책 구현. QR코드 안정 URL 유지.
- Rails Host 허용 목록과 프록시 Host 헤더 정책 일치.
- 독립 도메인별 쿠키 격리 및 로그인 흐름 테스트.

**완료 기준:** 두 도메인이 동일한 테넌트 사이트로 안전하게 연결되고, 타 테넌트 Host 위조가 차단된다.

### 3단계. Traccar Client 호환 GPS API

- OsmAnd GET/POST 파라미터 파싱. **타임스탬프는 현행 ISO8601 문자열 파싱을 유지하고, 숫자 타임스탬프(초/밀리초) 지원은 실기기 샘플 확보 후 추가한다(2026-10-18 결정).**
- lat/lon 범위, speed/bearing, accuracy, 배터리 등 필요한 필드 정규화.
- 장치 ID + 호환 가능한 인증 검증. HTTPS, 요청 크기 제한, rate limit 적용.
- **unknown-device 200-ack 계약 유지(2026-10-18 확정)**: 인증 실패만 401, 그 외(알 수 없는 단말·좌표 누락)는 200 ack로 무시한다. 4xx 반환 시 Traccar 포워딩 재시도 폭주를 피하기 위함.
- 기존 Traccar 수집 경로와 공통 PositionIngestor 서비스 추출.
- 측정 시각이 최신인 경우에만 CurrentPosition 갱신; 늦게 도착한 위치는 이력 정책에 따라 처리.
- 실패 응답·재시도·중복 요청에 대한 테스트.

**완료 기준:** 실제 Traccar Client가 새 서버로 정상 송신하고, 위치·시각·속도 값이 기존 Traccar와 일치한다.

### 4단계. Geofence 및 승객 지도

- 기존 정류장 도착 이벤트 로직을 재사용하거나 동일 결과로 재구현.
- 반경 진입/이탈 히스테리시스, 중복 이벤트 방지, 운행 방향 검증.
- 노선별 최신 위치 API 및 짧은 TTL 캐시.
- 10초 지도 갱신, 수신 지연 40~60초 표시, 위치 보간 시 실제 측정 시각 표기.
- GPS 30초 간격의 위치 지연·도착 이벤트 누락 비교 시험.

**완료 기준:** 승객 화면에 단일 추천 버스(`RouteBusSelector` 확장)가 정확히 표시되고, 관리자·지도 화면에서 다중 버스가 표시되며, 정류장 이벤트가 중복·누락 없이 생성된다.

### 5단계. 데이터 보존·운영

- CurrentPosition은 차량당 1행 유지. **테이블 신설 확정(2026-10-18).**
- PositionHistory는 **원본 24시간 보존(확정)**. 30초 샘플링은 후속 측정 후 검토.
- StopEvent는 **7일, 집계 통계는 90일로 확정(2026-10-18)**.
- SQLite WAL, busy_timeout, 짧은 트랜잭션, 인덱스 점검.
- 대량 DELETE 대신 소규모 배치 삭제; VACUUM/체크포인트는 운영 영향 측정 후 수행.
- SQLite 일관성 백업, 복원 연습, 모니터링 및 장애 대응 절차 작성.

**완료 기준:** 이력 자동 정리 중에도 GPS 수집과 승객 조회가 안정적으로 동작한다.

### 6단계. 1 vCPU / 1GB 부하 검증

- Puma 워커 0, 스레드 3~5부터 시작. Rails 프로세스 RSS 측정.
- 별도 Solid Queue 프로세스 실행 여부에 따른 RAM·CPU 비교.
- GPS 50대/10초(5 req/s), 100대/10초(10 req/s), 순간 30 req/s 시험.
- 승객 동시 조회는 **초기 목표 100명 기준(2026-10-18 결정)**으로 시험하고, 운영 실측 후 상향 시나리오(500/1,000명)를 검토한다. 관리자 페이지 접속 혼합 시험 포함.
- 24시간 연속 시험 및 배포 시 메모리 피크 확인.
- 실패하면 2GB RAM 증설 또는 프로세스·쿼리 구조 조정.

**완료 기준(초기 목표):** OOM 0건, DB 잠금 오류 0건, GPS 수집 p95 200ms 이하, 승객 서비스 가용성 99%·p95 응답 500ms, 메모리 상한 내 안정 동작. 목표는 실측 결과에 따라 조정.

### 7단계. Traccar 단계적 전환

- 테스트 장치 → 시범 노선 → 전체 노선 순으로 전환.
- 기존 Traccar와 새 서버의 위치·이벤트 비교 결과 기록.
- 되돌리기용 기존 서버 주소와 설정 보존.
- 앱 전송 실패, 배터리 소모, 백그라운드 제한, 네트워크 단절 복구 확인.
- 안정화 후 Traccar 서버 중단 여부 결정.

### 8단계. Roundhouse + Spinel PoC (선택)

- 수집기 최소 기능을 독립 가능한 모듈로 정리.
- Roundhouse/Spinel의 Rails 컨트롤러, HTTP, SQLite 연결, 인증 라이브러리 지원 여부 검증.
- Ruby/Puma 대비 실행 파일 크기, RSS, CPU, 응답 지연, 배포 난이도 비교.
- 전체 시스템 메모리 절감이 확인될 때만 도입.

## 6. API 초안

| 메서드 | 경로 예시 | 기능 |
| --- | --- | --- |
| GET/POST | `/gps` (또는 앱 호환 루트) | OsmAnd GPS 수신 |
| GET | `/api/routes/:id/positions` | 현재 테넌트 노선의 차량 최신 위치 |
| GET | `/api/stops/:id/arrivals` | 정류장 도착 정보 |
| GET | `/admin/devices` | 테넌트 관리자 장치 상태 |
| POST | `/platform/tenants` | 플랫폼 관리자 테넌트 개설 |
| POST | `/admin/domains` | 독립 도메인 연결 신청 |

기존 라우트와 충돌하지 않도록 저장소 조사 후 최종 경로 확정.

> **2026-10-18 결정:** `/platform/tenants`, `/admin/domains` 등 테넌트·도메인 관련 엔드포인트는 멀티테넌트 보류에 따라 이번 범위에서 제외한다.

## 7. 테스트 매트릭스

| 항목 | 테스트 |
| --- | --- |
| 호환성 | Traccar Client GET/POST, 시간 단위, 오프라인 재전송 |
| 보안 | 위조 장치 ID, 잘못된 토큰, Host 헤더 위조, 교차 테넌트 조회 |
| GPS 품질 | GPS 튐, 순서 역전, 중복 수신, 30초 간격 정류장 통과 |
| DB | 동시 쓰기, 정리 작업 중 잠금, WAL 체크포인트, 복원 |
| 화면 | 노선당 5대, 지연 위치, 도메인별 테마, QR코드 |
| 성능 | 1 vCPU/1GB에서 GPS·승객·관리자 혼합 부하 |
| 배포 | 재시작, 롤백, 영구 볼륨 보존, TLS 갱신 |

> **2026-10-18 결정:** 테넌트 관련 항목(교차 테넌트 조회, 도메인별 테마)은 멀티테넌트 보류에 따라 이번 구현 범위에서 제외한다.

## 8. 주요 위험과 대응

- **1GB 메모리 부족:** Rails + 작업자 + 배포 피크를 실측하고 2GB 상향 경로 준비.
- **SQLite 쓰기 경합:** 수집 트랜잭션 최소화, 최신 위치/이력 분리, 샘플링, 인덱스 점검.
- **GPS 인증 호환성:** Traccar Client 설정을 확인하고 서버 측 비밀값 검증을 별도 설계.
- **지자체 데이터 누출:** 모든 모델/컨트롤러/잡/캐시 경로에서 격리 테스트. (멀티테넌트 보류 결정에 따라 이번 범위에서 제외, 확장 시 재검토)
- **30초 수집 시 도착 이벤트 누락:** 기본 10초 유지, 30초는 실제 노선 데이터로 검증 후 선택.
- **독립 도메인 운영:** DNS 검증, 인증서 자동화, 만료·도메인 탈취 감지.
- **Roundhouse/Spinel 미지원 기능:** 운영 경로와 분리된 PoC로 유지.

## 9. 우선순위와 산출물

| 우선순위 | 작업 | 산출물 |
| --- | --- | --- |
| P0 | 저장소·Traccar 연동 조사 | 현행 구조도, 변경 대상 파일 목록 |
| P0 | 1GB 단일 서버 기준선 검증(부팅·유휴·GPS 수신·승객 폴링 부하 RSS) | RSS·부하 측정 보고서 |
| P0 | CurrentPosition/PositionHistory 구조 확정 | 스키마 마이그레이션안 |
| P0 | GPS 수신 호환 API | 요청 명세, 실기기 테스트 |
| P0 | SQLite/1GB 성능 검증 | 부하 테스트 보고서 |
| 보류 | 테넌트 모델·권한·데이터 격리(2026-10-18 결정: 이번 계획에서 제외) | 향후 별도 검토 |
| 보류 | 도메인 자동화·테마(테넌트 보류에 따름) | 향후 별도 검토 |
| P1 | 노선 지도·위치 캐시 | 승객 지도 API 및 UI |
| P1 | Traccar 단계적 전환 | 전환·롤백 운영 문서 |
| P2 | Roundhouse + Spinel | PoC 및 성능 비교 보고서 |

> **2026-10-18 결정:** P0 실행 범위는 위 "0.5. P0 실행 범위" 섹션과 `.omo/plans/datalogger-p0-execution.md`의 10개 todo로 확정됐다. 테넌트 모델·도메인 자동화는 보류다.

## 10. 구현 시작 전 확인 질문

1. 실제 운영할 지자체 수와 각 지자체별 최대 버스 수는 얼마인가?
2. 운전자 앱은 Traccar Client와 Flutter 앱 중 무엇을 사용하는가? **(확정, 2026-10-18: 현행 Flutter + Traccar Client SDK + PIN 1회용 인증 유지)**
3. 기존 Traccar의 Geofence/Webhook을 어디까지 재현해야 하는가?
4. 1GB 서버에서 관리자와 승객 페이지까지 모두 제공하는가? **(확정, 2026-10-18: 예 — 단일 소규모 서버에 관리자·승객·GPS 수신기를 동봉 실행)**
5. 독립 도메인의 DNS/TLS 관리는 운영자가 직접 하는가, 자동 셀프서비스로 제공하는가? (테넌트 보류 결정에 따라 보류)

## 11. P0 구현 결과 (2026-10-18)

`.omo/plans/datalogger-p0-execution.md`의 10개 todo를 모두 완료했다.

### 11.1 주요 파일

| 구성 요소 | 파일 |
| --- | --- |
| PositionIngestor | `app/services/position_ingestor.rb` |
| StopEventDetector | `app/services/stop_event_detector.rb` |
| Traccar 포워딩 컨트롤러 | `app/controllers/integrations/traccar_controller.rb` |
| OsmAnd /gps 컨트롤러 | `app/controllers/gps_controller.rb` |
| 지도 컨트롤러·뷰·JS | `app/controllers/map_controller.rb`, `app/views/map/show.html.erb`, `app/javascript/controllers/map_controller.js`, `app/javascript/map_providers/*` |
| RouteBusSelector 확장 | `app/services/route_bus_selector.rb` |
| 배경 잡 | `app/jobs/trip_auto_terminator_job.rb`, `app/jobs/retention_job.rb`, `app/jobs/route_segment_stat_aggregator_job.rb`, `config/recurring.yml` |
| 설정 상수 | `config/initializers/datalogger.rb` |
| 모델 | `app/models/current_position.rb`, `app/models/position_history.rb`, `app/models/stop_event.rb`, `app/models/route_segment_stat.rb`, `app/models/device.rb` |
| 구간 통계 집계 | `app/services/route_segment_stat_aggregator.rb` |
| 마이그레이션 | `db/migrate/20261018*_create_*.rb` |
| 테스트 | `test/services/position_ingestor_test.rb`, `test/services/stop_event_detector_test.rb`, `test/controllers/integrations/traccar_controller_test.rb`, `test/controllers/gps_controller_test.rb`, `test/controllers/map_controller_test.rb`, `test/jobs/trip_auto_terminator_job_test.rb`, `test/jobs/retention_job_test.rb` |

### 11.2 설계 변경 및 결정

- `RouteBusSelector`는 `:passenger`(단일 추천 버스)와 `:map`/`:admin`(GPS 있는 모든 버스) 컨텍스트를 지원한다.
- `PositionIngestor`는 Traccar 포워딩과 `/gps` 모두에서 호출되며, `CurrentPosition` upsert 시 `recorded_at` 역전을 방지한다.
- `StopEventDetector`는 approach(200m)/arrive(30m)/depart(100m) 히스테리시스와 dedup_key로 중복을 방지한다.
- 숫자 타임스탬프는 501 Not Implemented를 반환하며, ISO8601 문자열만 지원한다.
- `arrival_polling_controller.js` 폴리ng 주기는 5000ms에서 10000ms로 변경됐다.

### 11.3 검증 결과

- `bin/rails test`: 113 tests, 339 assertions, 0 failures, 0 errors, 0 skips (2026-10-18)
- `bin/rubocop`: 122 files inspected, no offenses
- `bin/rails db:migrate` (dev/test): 성공
- CI에 테스트 잡이 없으므로 테스트 통과는 로컬 실행으로 검증했다(AGENTS.md §테스트). 작업별 근거는 `.omo/evidence/task-1-datalogger-p0-execution.md` ~ `task-9-datalogger-p0-execution.md` 참고.

### 11.4 PR #21 리뷰 반영 (2026-10-19)

WIP 리뷰(hye-k) 지적 사항을 반영했다.

- **노선 지도 렌더링 수정**: `show.html.erb`의 `raw ... to_json`을 제거해 `data-*` 속성 JSON이 HTML 이스케이프로 안전해졌고, 좌표는 `to_f`로 숫자 직렬화한다. Google Maps script의 `callback=initMapProvider`는 head 인라인 스크립트에서 정의해 `google-maps:ready` 커스텀 이벤트를 발행하고, `map_controller.js`는 `google` 객체가 없으면 이 이벤트를 기다렸다가 렌더링한다. provider 3개의 상대 import(`./base_map_provider`)를 importmap 핀 경로(`map_providers/base_map_provider`)로 바꿨고, 지도 루트를 `h-screen`으로 바꿔 캔버스 높이가 0이 되지 않게 했다. `map_controller_test.rb`는 응답 HTML의 속성 값을 JSON 파싱해 검증한다.
- **stale-GPS 이벤트 방지**: `PositionIngestor`는 `CurrentPosition`이 실제 갱신된 경우(updated)에만 `StopEventDetector`를 호출한다. 운전자 앱 버퍼 재전송(원본 timestamp 유지)으로 시각 역전이 와도 가짜 도착·출발 이벤트가 생기지 않는다. GpsLog·PositionHistory 기록은 계속 유지된다.
- **구간 통계 집계 구현**: `StopEventDetector`가 arrive 이벤트를 생성하면 `RouteSegmentStatAggregatorJob`을 enqueue하고(Solid Queue, 트랜잭션 커밋 후 실행), `RouteSegmentStatAggregator`가 같은 버스의 직전 `depart` 이벤트와 쌍을 이뤄 구간 소요 시간을 집계한다. 쌍 인정 조건: depart 정류장은 arrive 정류장 바로 이전 순번(sequence - 1), 소요 시간은 0초 초과 2시간 이하. 집계 단위는 `(route_id, from_stop_id, to_stop_id, hour_of_day, date)` — hour/date는 arrive 시각 기준 — 이며 unique index로 중복을 막고 표본 평균(`avg_seconds`, `samples_count`)을 upsert한다.
- **`/gps` timestamp 계약 명시**: `/gps`는 ISO8601 timestamp만 지원하며 숫자 epoch timestamp는 `501 Not Implemented`로 거부한다(의도적 차단). SDK의 epoch 초 직접 연동은 후속 작업이다. `docs/osmand-request-samples.md` §4.3/§5, `docs/driver-app-local-rails-test.md`에 동일하게 반영했다.
