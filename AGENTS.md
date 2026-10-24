# AGENTS.md — 내 버스는 언제 올까? (where-is-my-bus)

소규모 BIS 버스정보시스템. 시골, 도서 지역 노선버스 실시간 위치 서비스.

## 모노레포 구조

| 경로 | 내용 |
|---|---|
| 루트 | 웹 애플리케이션 (Rails 8.1, Ruby 4.0.9 — `.tool-versions`/`.ruby-version` 고정) |
| `driver_app/` | 버스 운전자용 Flutter 앱 (GPS 송신). **Rails와 별도로 빌드·배포되는 앱** — register/positions/routes API 계약으로 강결합 |
| `docs/` | `traccar-integration.md` — Traccar 연동 설계·계약의 원본 문서 |
| `driver_app/README.md` · `driver_app/ISSUE.md` | 운전자 앱 설정 근거·임시 설정(원복 필요) 목록 |

**CI·배포 분리**: 루트 CI(`.github/workflows/ci.yml`)는 `driver_app/**` 변경을 무시(`paths-ignore`), Kamal Docker 이미지에도 제외(`.dockerignore`). Flutter용 CI는 아직 없음 — `driver_app` 작업은 로컬 검증 필수(아래 스킬 참고).

## 기술 스택

- Rails 8.1 + Ruby 4.0.9, **SQLite**(prod도 파일 DB: `storage/production{,_cache,_queue,_cable}.sqlite3`)
- Hotwire(Turbo/Stimulus) + importmap + **Tailwind CSS 4** (`tailwindcss-rails ~> 4.4`)
- 인증: Rails 8 내장(세션 쿠키 + `has_secure_password`, bcrypt) — Devise 없음
- Solid Queue / Solid Cache / Solid Cable, Kamal + Thruster, Propshaft
- 스타일: `rubocop-rails-omakase`

## 도메인 모델 (db/schema.rb, Rails 8.1)

```
Region (시·도, slug, position)
  └─ Area (운행지역)  [counter_cache: areas_count]
       ├─ Route (노선, headway_minutes) [counter_cache: routes_count] — `likes_count` 컬럼은 있으나 현재 counter cache 미사용·갱신 로직 없음(admin 화면은 컬럼값 그대로 표시); 승객 화면의 좋아요 수는 정류장별 `StopLike` 실시간 count
       │    ├─ Stop (정류장, sequence 순서, lat/lng, avg_travel_seconds) [counter_cache: stops_count]
       │    └─ RouteBus (join table — Route↔Bus N:N 배차)
       └─ Bus (차량, license_plate, bus_number, pin, traccar_unique_id, status enum)
Trip (버스 1회 운행 — ended_at: nil 이면 활성) ─▶ GpsLog (lat/lng/recorded_at)
StopLike (session_token 기반, 1시간 내 1회) / Session / User
```

- `User` role enum: `member`(0) / `operator`(1). **첫 가입자가 자동으로 operator**(`before_create`에서 `User.count.zero?` 검사) — 가입 폼에서 role을 받지 않는다.
- **함정 — `PinCode`는 레거시 모델이며 현재 등록 API(PIN 인증)에는 사용하지 않는다.** 마이그레이션·schema·`Bus has_many :pin_codes` 연관·`db/seeds.rb` 데모 레코드 생성은 존재하지만, 실제 PIN 인증은 `Bus.pin` 컬럼(`buses.pin`, unique)으로 이뤄진다. (`docs/traccar-integration.md` 명시)
- **`default_scope` 주의** — 아래 5개 모델은 전역 정렬이 항상 걸려 있다(`unscoped` 필요 시 명시):
  `Region`·`Area`·`Route`는 `position, name`순, `Stop`은 `sequence`순, `Bus`는 `license_plate`순.
- PIN(자동 발급은 6자리 숫자; 유효성 검사는 4~6자리 허용)·`traccar_unique_id`(자동 생성은 hex 12자 — seed·기존 데이터는 예외, 예: `goseong-1-demo`)는 Bus 생성 시 자동 발급(`SecureRandom`, before_validation). 운영자가 수동 입력하지 않는다.
- 정류장 좌표(`lat/lng`): **DB 스키마는 nullable, 모델 validation은 필수**(`validates :lat, :lng, presence: true`). 크라우드소싱(좌표 없이 등록)을 지원하려면 validation 완화가 필요 — 그 전까지는 앱 경로로는 null 좌표가 안 생기지만, fixture/직접 SQL로 null이 들어가면 `RouteProgress`의 거리 계산이 `nil.to_f = 0.0`으로 **조용히 왜곡**된다(에러 없음). `Stop#coordinates?` 헬퍼로 좌표 유무를 확인할 수 있다.

## 레이어 구조

```
app/
  controllers/
    admin/            — 운영자 CRUD (regions/areas/routes/stops/buses/route_buses/guides)
    integrations/     — traccar_controller.rb (머신 간 수신 API)
    stops_controller.rb — 승객 서비스 (/r/:region_slug/:stop_id)
  services/
    traccar_group_sync.rb        — Route → Traccar Group
    traccar_geofence_sync.rb     — Stop → Traccar Geofence (중심 30m 정사각형)
    traccar_group_membership.rb  — 배차(RouteBus) ↔ Group ↔ device 연결
    traccar_device_sync.rb       — Bus → Traccar device 프로비저닝
    route_bus_selector.rb        — 배차 버스 중 승객 화면에 보여줄 버스 선택
    concerns/traccar_api_client.rb — 공통 HTTP 클라이언트 (Net::HTTP, Result 패턴)
  models/route_progress.rb — ETA 계산 (승객 화면·운전자 앱 공유)
  javascript/controllers/  — arrival_polling, bus_selector, like_button
```

## 인증·권한

- `Authentication` concern이 **전역** `require_authentication` — 공개 페이지는 컨트롤러에서 `allow_unauthenticated_access`로 명시적 해제(예: `StopsController`, `PagesController`).
- `Admin::BaseController`가 `require_operator` 강제 — admin 하위 컨트롤러는 모두 이걸 상속. 새 admin 컨트롤러 추가 시 `Admin::` 네임스페이스 + 상속 유지.
- 세션: signed 쿠키 `session_id` → `sessions` 테이블. 테스트 헬퍼 `sign_in_as(user)`가 실제 `POST /session`을 날린다.
- 레이아웃 3종: `admin` / `service`(승객) / `application`(기타).

## Traccar 연동 (핵심 아키텍처)

데이터 흐름: 운전자 폰(`driver_app` → traccar_client_sdk, OsmAnd :5055) → Traccar 서버(Docker, API :8082) → 위치 포워딩(JSON POST) → Rails `/integrations/traccar/positions` → Trip → GpsLog → 승객 화면 폴링(5초)으로 반영.

### 수신 API (`Integrations::TraccarController`, `ActionController::API`)

| 엔드포인트 | 계약 |
|---|---|
| `POST /integrations/traccar/register` | `{ pin }` → `200 { traccarServerUrl, deviceId }`. 실패: `401`(PIN 불일치) / `409`(PIN 1회용 소모됨) / `429`(IP당 5회 실패 → 15분 잠금, `Rails.cache` 기반) |
| `POST /integrations/traccar/positions` | Traccar 포워딩 수신. `X-Ingest-Token` 헤더 인증(timing-safe, 실패 `401`). **인증 성공 후 알 수 없는 단말·좌표 누락은 `200` ack로 무시** — 4xx 반환하면 포워딩 재시도 폭주 |
| `GET /integrations/traccar/routes?deviceId=` | driver_app 메인화면용. `busNumber/routeName/stops/nextStop` 묶음. ETA는 `RouteProgress` 공유 |

- **PIN은 1회용**: 성공 시 조건부 UPDATE(`pin_registered_at` 찍기)로 원자적 소모. 기기분실/교체는 admin "PIN 재발급"(`Bus#regenerate_pin!`)이 `pin_registered_at`도 초기화.
- **credentials 접근은 경로별로 다르다**:
  - 수신 컨트롤러(`Integrations::TraccarController`)의 `ingest_token`·`server_url`: `credentials[:traccar][:...]` → `ENV["TRACCAR_..."]` → 개발 기본값(`Rails.env.local?`일 때만). 운영 미설정 시: `ingest_token`은 모든 positions가 `401`(**fail-closed**, 수신 전면 중단), `server_url`은 register 응답의 `traccarServerUrl`이 `nil`.
  - sync 서비스(`TraccarApiClient`)의 `api_base_url`/`api_email`/`api_password`: **credentials만** 읽는다(ENV fallback 없음 — 구현 미설정). 미설정 시 `CredentialsMissing` → `failure?` Result로 반환되어, Route/Stop/Bus의 일반 create/update는 validation 실패와 동일한 `422`로, **RouteBus 생성은 redirect + flash alert**로 처리된다. 단, **예기치 않은 예외까지 500을 막는 것은 아니다**.
- ⚠️ `traccar_server_url` 개발 기본값은 내부 테스트 서버(`yehyunserver.iptime.org`)로 임시 고정 — 원복 목록은 `driver_app/ISSUE.md` "임시 설정" 섹션.

### Admin CRUD ↔ Traccar 정합성 (완전 롤백 정책)

Route/Stop/Bus는 생성·수정·삭제, RouteBus는 배차 생성·해제 작업을 Traccar API 호출과 **하나의 트랜잭션처럼** 취급한다. 구현 방식: 생성·수정은 `ActiveRecord::Base.transaction` 블록 안에서 Traccar sync 실패 시 raise로 롤백. **삭제는 Route/Stop/Bus가 Traccar 리소스(group/geofence/device) 삭제 성공 후 Rails destroy이고, RouteBus는 리소스 삭제가 아니라 device를 group에서 해제(`groupId → NO_GROUP(0)`)한 뒤 RouteBus destroy** — RouteBus 반납 시 Traccar group·geofence·device는 유지됨. 둘 다 "Traccar 측 선행조건이 없으면 Rails 레코드도 없다" 원칙 — 드리프트 원천 차단. 단, **외부 HTTP 호출 자체는 롤백되지 않는다**.

- ⚠️ 외부 HTTP는 롤백되지 않으므로 트랜잭션 도중 실패 시 Traccar에만 리소스가 남는(생성은 됐는데 Rails는 롤백된) orphan 가능성 — 예: Traccar 생성은 성공했는데 응답 파싱 실패(`JSON::ParserError`는 서비스가 rescue)로 failure 반환. **기존 Rails 레코드와 Traccar ID가 남아 있는 정합성 불일치는 수동 sync 액션으로 복구할 수 있다**(`sync_group`(routes) / `sync_geofence`(stops) / `sync_device`(buses)). **Rails 레코드 자체가 소실된 orphan 리소스는 sync 액션으로 복구 불가** — Traccar 콘솔에서 삭제하거나 별도 reconciliation 작업이 필요하다.
- ⚠️ **예외 — Route 수정은 Traccar sync를 호출하지 않는다**: `Admin::RoutesController#update`는 `@route.update(route_params)`만 실행(반면 Stops·Buses의 update는 transaction+sync 적용). 노선명·운행지역 변경 시 Traccar group 이름이 stale 상태로 남을 수 있음 — `sync_group` 수동 재동기화로 회복.
- ⚠️ **예외 — 배차(RouteBus)는 Traccar device 미프로비저닝이어도 Rails 레코드가 저장될 수 있다**: `TraccarGroupMembership.add`는 `bus.traccar_device_id`가 없으면 **조기 반환으로 group sync 자체도 생략하고 성공**으로 취급한다(예: 시드 데모 버스). device가 있는 경우에만, group이 없으면 `TraccarGroupSync`로 group을 확보한 뒤 device를 연결한다. — "Traccar 측 선행조건이 없으면 Rails 레코드도 없다" 원칙은 Route/Stop/Bus 기준이며 RouteBus에는 이 예외가 있다.
- ⚠️ **반대 방향의 drift도 존재** — 삭제는 "Traccar 먼저 → Rails destroy" 순서이므로, Rails `destroy`가 실패하면(예: DB 예외) Traccar 리소스는 이미 삭제되고 Rails 레코드만 남는다. **복구 절차는 구현돼 있지 않다** — id가 남은 채 `sync_*`를 호출하면 서비스가 새 리소스를 만드는 게 아니라 기존(삭제된) Traccar ID에 update(PUT)를 시도해 실패한다(id.present? → update 분기). 복구 수단: Rails 콘솔/SQL에서 `traccar_group_id`·`traccar_geofence_id`·`traccar_device_id`를 nil로 리셋한 뒤 해당 sync 액션 실행(id가 비면 create 경로), 또는 Traccar 콘솔에서 새 리소스를 만들고 Rails 측 id를 수동 갱신. 단, **sync 액션은 단일 리소스만 재생성** — group 재생성 후 각 Stop의 geofence↔group permission은 `sync_geofence`(정류장별) 재실행으로 복원하며, device 재생성 후 배차 membership는 수동 sync 액션이 없으므로 admin에서 배차 해제→재배차로 재연결하거나 콘솔 수동 작업이 필요하다.
- 트레이드오프: Traccar 서버 다운 시 **Traccar sync가 필요한** admin 생성·수정·삭제 작업이 실패한다(화면에 실패 사유 표시). 별도 예외 — Route 수정(sync 미호출)·미프로비저닝 Bus의 RouteBus 배차(membership 스킵)·Region/Area CRUD(Traccar 무관)는 계속 동작한다.

- services는 `TraccarApiClient` concern 사용: `Result` struct(**필드 `success` + `failure?` 메서드 — `success?`는 정의 없음**, 참값은 `result.success`로 직접 확인), `RESCUED_ERRORS` 목록에 오류 추가, 테스트는 클래스메서드 `stub_credentials(base_url:, email:, password:)`로 주입.
- 연결 구조는 노선 단위 **Group 간접 연결**(개별 geofence↔device 연결 금지): Stop geofence → Route Group에 연결, 배차 시 Group에 device 추가. 정류장 추가·버스 배차가 서로를 건드리지 않게 함.
- Traccar 자원 이름 규칙: group = `"{운행지역} {노선명}"`, geofence = 정류장명 (`route-{id}`/`stop.id` 방식에서 변경된 이력 있음).

### ETA 로직 공유 (중복 금지)

- `RouteProgress` — 최신 GPS ↔ 정류장 비교 ETA. **승객 화면(`StopsController#arrival`)과 운전자 앱(`traccar#routes`)이 반드시 이 클래스를 공유**. 두 화면이 다른 숫자를 보이는 버그를 막는 핵심 설계.
- `RouteBusSelector` — show/detail/arrival이 배정 버스 중 활성 trip + GPS 있는 버스 중 `stops_away` 최소를 선택. 새 UI가 ETA를 보여야 하면 이 둘을 재사용, 직접 계산하지 않는다.

## 프론트엔드 (승객 화면)

- 실시간: **폴링 5초**(`arrival_polling_controller.js`, `document.hidden` 시 스킵). Solid Cable 도입은 보류 결정 — WebSocket으로 바꾸려면 `docs/traccar-integration.md` 결정 사항을 먼저 뒤집어야 한다.
- 응답 status 의미: `no_trip`(운행 중 버스 없음) / `no_data`(운행 중이나 GPS 미수신) / 그 외(정상). GA4 `arrival_status` 이벤트의 분류와 동일.
- `StopsController#show/detail`은 `no_turbo_cache` before_action — Turbo 캐시 복원 시 시간이 오래된 ETA가 보이는 걸 방지.
- GA4: 스크립트는 `layouts/service.html.erb`에서 `Rails.env.production?`일 때만 로드(Measurement ID `G-V5FQ7DHE99`). `app/javascript/ga4.js`는 `ga4Event` 헬퍼. 정류장 페이지는 가상 page_path(`/:지역명/:버스번호/:정류장명`) 사용(`content_for(:ga4_page_path)`) — 실제 URL(`/r/:region_slug/:stop_id`)과 다름. 이벤트: `arrival_status`, `like_stop`, `select_bus`, `view_detail`. 상세는 README "Google Analytics 4" 섹션.
- 개발 전용: `POST /r/.../debug_bus` — `seq`(정류장 순번)·`pct`(구간 진행률 %)로 가짜 버스 위치 주입 + `debug:refresh` 이벤트로 폴링 즉시 반영.

## 테스트 (Minitest)

```bash
bin/rails test                                   # 전체
bin/rails test test/services/traccar_group_sync_test.rb  # 단일 파일
```

- Minitest + fixtures(`fixtures :all`) + WebMock(`disable_net_connect!(allow_localhost: true)`).
- Traccar API stub: 서비스 테스트는 `stub_credentials` 사용 — WebMock으로 `/api/...` 요청을 stub.
- admin 컨트롤러 테스트는 `sign_in_as(user)` 헬퍼(`test/test_helper.rb`) — 실제 세션 엔드포인트를 거쳐 signed 쿠키가 심긴다.
- ⚠️ **CI(GitHub Actions, `bin/ci`)에는 테스트 잡이 없다** — brakeman / bundler-audit / importmap audit / rubocop만 돈다. 테스트는 로컬에서 직접 실행해야 검증된다. (README "테스트는 --skip-test로 생략" 메모는 outdated — 현재 `test/`에 모델·컨트롤러·서비스 테스트 존재)

## 개발 명령

```bash
bin/setup                 # 초기 세팅
bin/rails db:prepare      # 스키마 생성 + 시드 (고성군 고성↔통영 1번 노선 데모 — idempotent, find_or_create_by!)
bin/dev                   # 서버(web) + Tailwind watch(css) 동시 실행 (Procfile.dev)
bin/rails test            # 테스트
bin/ci                    # rubocop + gem/importmap audit + brakeman (CI와 동일, 테스트 제외)
bin/rubocop               # 스타일
```

- 시드 PIN `1234`, 데모 `traccar_unique_id: "goseong-1-demo"` — `db/seeds.rb` 참고.
- `bin/dev`는 `Procfile.dev` 그대로: `web: bin/rails server`, `css: bin/rails tailwindcss:watch`.

## 배포

- Kamal (`config/deploy.yml`) — **현재 placeholder 상태**(서버 `192.168.0.1`, registry `localhost:5555`, service `web`). 실배포 전 주소 확정 필요.
- `SOLID_QUEUE_IN_PUMA: true` — Solid Queue를 Puma 프로세스 안에서 구동(별도 worker 서버 없음).
- `RAILS_MASTER_KEY`는 `.kamal/secrets`에서 주입. SQLite 파일은 Docker 볼륨으로 영속화.
- GA4 Measurement ID `G-V5FQ7DHE99`는 production에서만 로드(`Rails.env.production?`).

## 알려진 함정·주의사항

1. **PinCode는 레거시 모델, 인증 미사용** — PIN은 `Bus.pin`. 새 기능에서 `PinCode`를 건드리지 말 것.
2. **임시 설정 원복 대기** — `driver_app/ISSUE.md` 상단 "임시 설정 (원복 필요)" 섹션: Rails `traccar_server_url` 로컬 기본값, Android cleartext `network_security_config.xml`.
3. **ETA/버스 선택 중복 구현 금지** — `RouteProgress`/`RouteBusSelector` 재사용.
4. **positions는 401 예외를 제외하고 항상 200-ack** — 토큰 인증 실패는 `401`, 그 외(알 수 없는 단말·좌표 누락)는 `200` ack. 검증 실패를 4xx로 반환하면 Traccar 포워딩 재시도 폭주.
5. **`buses.pin` unique 전역 인덱스** — register API가 PIN만으로 버스를 특정하므로 필수. 변경 시 주의.
6. 버스당 노선 1개 가정: `traccar#routes`가 `bus.routes.first`(position순) 사용. N:N 배차가 일반화되면 재검토.
7. 문서 최신성: `docs/traccar-integration.md`(설계 원본), `driver_app/ISSUE.md`(설정 근거), README의 GA4·어드민 변경 로그 — 큰 변경은 여기도 갱신.
8. **첫 가입자 operator 승격의 동시성 race 미해결** — `User#assign_operator_if_first_user`가 `User.count.zero?`로 판정하므로, 동시 가입 요청이 겹치면 두 번째 가입자도 operator가 될 수 있다. 현재 구현은 사실이지만 DB 유니크 제약 없는 로직 기반 정책임을 알고 변경할 것.
9. **Route 수정 시 Traccar group 미동기화** — 위 "완전 롤백" 섹션의 예외 항목. `update`가 sync를 호출하지 않는 현재 동작과 `docs/traccar-integration.md`의 설계("Route 생성/수정 → Group 생성")가 서로 다름 — 노선명 변경 후에는 `sync_group`으로 정합성 회복, 또는 구현을 설계에 맞춰야 함.

## 코딩 관례

- 커밋 메시지: `feat:`, `fix:`, `chore:`, `docs:` 접두어 + 한국어 설명 (git log 관례).
- UI 문구·주석은 한국어 기본. 모델의 ko/en 컬럼(`name`/`name_en`)과 `I18n.locale` 분기 패턴 유지.
- RuboCop omakase 스타일 준수 — 커스텀 규칙 없음(`.rubocop.yml`은 inherit_gem만).
