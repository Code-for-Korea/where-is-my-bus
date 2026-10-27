# AGENTS.md — 내 버스는 언제 올까? (where-is-my-bus)

소규모 BIS 버스정보시스템. 시골·도서 지역 노선버스의 위치를 **정류장 단위**로 알려 준다.
매 세션마다 읽어서 짧게 유지. 상세 설계 `docs/` 문서 연결, 여기는 구조, 명령, 관례, 함정 작성.

## 구조

| 경로 | 내용 |
|---|---|
| 루트 | 웹 애플리케이션 (Rails 8.1, Ruby 4.0.9 — `.tool-versions`/`.ruby-version` 고정) |
| `driver_app/` | 버스 운전자용 Flutter 앱. Rails와 별도로 빌드·배포되며 `integrations/traccar/*` API 계약으로 강결합 |
| `docs/` | 설계, 정책 문서 (아래 "문서 지도") |

기술 스택: SQLite(prod도 파일 DB), Hotwire + importmap, Tailwind CSS 4, Solid Queue/Cache/Cable, Kamal, Propshaft, 인증은 Rails 8 내장(Devise 없음). 스타일은 `rubocop-rails-omakase`(커스텀 규칙 없음).

## 핵심 아키텍처 (한 줄 요약)

운전자는 앱으로 위치를 **Traccar**로 보내고, Traccar가 정류장 **Geofence 진입/이탈 이벤트**를 Rails(`POST /integrations/traccar/events`)로 포워딩하면 Rails가 `stop_visits`에 방문을 기록한다. **Rails는 GPS 좌표를 저장하지 않고 ETA도 계산하지 않는다.**

```
Route ─< RouteStop >─ Stop          (정류장은 독립 객체, 여러 노선이 공유)
Route ─< Bus                        (buses.route_id: 차량 1대에 노선 1개 배정)
Bus ─< Trip ─< StopVisit >─ Stop    (Trip.ended_at nil = 진행 중, 버스당 1개)
User ─< Session                     (role: member / operator)
```

레이어: `controllers/admin/`(운영자 CRUD) · `controllers/integrations/`(앱·Traccar 머신 간 API) · `services/`(Traccar 동기화 `Traccar*`, `*Registration`, 운행·방문 `Trip*`/`StopVisitRecorder`/`RouteBusStatuses`) · `presenters/arrival_presenter.rb`(승객 화면). 승객 화면은 5초 폴링(`arrival_polling_controller.js`).

## 문서 구성

| 구분 | 문서 |
|---|---|
| Traccar 자원 대응, 이벤트 흐름, 설정, 실측 동작, 보안 | `docs/traccar-integration.md` |
| 설계 결정과 근거, 이벤트 페이로드(6절) | `docs/design-event-driven-rewrite.md` |
| 데이터 모델 변경 목적 / ERD | `docs/data-model-rewrite.md`, `docs/erd.md` |
| 로컬 데모 실행 | `docs/local-demo.md` |
| 운영 배포(Kamal), 백업, 마이그레이션 | `docs/deployment.md` |
| 제품 요구사항, 정책 초안, 남은 과제 | `docs/product_requirements.md`, `docs/policy-draft.md`, `docs/future-improvements.md` |
| 운전자 앱 | `driver_app/README.md`, `driver_app/mvp-spec.md`, `driver_app/ISSUE.md` |

Traccar 연동·`driver_app` 코드를 고칠 때는 프로젝트 스킬 `traccar-sync`, `driver-app`(`.claude/skills/`)을 먼저 쓴다. 두 스킬은 재작성 이후 구조 기준이다.

## 인증·권한

- `Authentication` concern이 **전역** `require_authentication` — 공개 컨트롤러는 `allow_unauthenticated_access`로 명시적 해제(`StopsController`, `ArrivalsController`, `PagesController` 등).
- `Admin::BaseController`가 operator를 강제 — admin 컨트롤러는 `Admin::` 네임스페이스와 이 상속을 유지한다.
- `integrations/*`는 `ActionController::API`(세션 없음). 이벤트 수신은 `X-Ingest-Token`(timing-safe), 앱 API는 `deviceId`(= `buses.traccar_unique_id`)로 버스를 식별한다.
- 레이아웃 3종: `admin` / `service`(승객) / `application`(기타).

## 개발·테스트 명령

```bash
bin/setup                           # 초기 세팅
bin/dev                             # Rails + Tailwind watch (Procfile.dev). Traccar는 포함되지 않는다
docker compose up -d --build        # Rails + 로컬 Traccar 데모 (docs/local-demo.md)
bin/rails "demo:drive[1번]"         # 시뮬레이터로 버스 한 대 운행 (compose 안이면 docker compose exec rails ...)
bin/rails db:prepare                # 스키마 + 시드 (idempotent)
bin/rails test                      # Minitest (fixtures :all, WebMock). 단일 파일: bin/rails test test/services/xxx_test.rb
bin/ci                              # rubocop + gem/importmap audit + brakeman (CI와 같은 구성, 테스트 제외)
```

- 테스트 헬퍼 `sign_in_as(user)`는 실제 `POST /session`을 거친다. Traccar API는 WebMock으로 stub한다.
- ⚠️ **CI(GitHub Actions)에는 테스트 잡이 없다** — brakeman / bundler-audit / importmap audit / rubocop만 돈다. 테스트는 로컬에서 직접 돌려야 검증된다. `driver_app`은 CI가 아예 무시하므로(`paths-ignore`) 로컬에서 `flutter test`·`flutter analyze`가 필수다.
- ⚠️ bundler-audit 결과는 **advisory DB가 오래되면 CI와 달라진다** — 로컬에서 `bundle exec bundle-audit update` 후 확인한다.
- Traccar 접속 설정은 **환경변수 → credentials 순서**(`TRACCAR_API_BASE_URL`/`TOKEN`, `TRACCAR_INGEST_TOKEN`, `TRACCAR_SERVER_URL`). 로컬 기본값은 `compose.yaml`의 `environment`에 있다. 표는 `docs/traccar-integration.md`.

## 배포

Rails만 Kamal(`config/deploy.yml`)로 배포하고 Traccar는 별도 서버를 쓴다. 이미지는 **공개 Docker Hub**라 비밀값·개발 자료가 들어가지 않도록 `.dockerignore`를 관리한다. `deploy.yml`의 `DOCKERHUB_USER`, `SERVER_IP`는 아직 자리표시자다. `RAILS_MASTER_KEY`는 `.kamal/secrets`가 `config/credentials/production.key`에서 주입하고(키는 git·이미지에 없음), 운영 설정은 `production.yml.enc`에 둔다. SQLite는 컨테이너 밖 호스트 디렉터리에 두고 `bin/backup-storage`로 백업한다. 운영에서는 `db:seed`가 실행되지 않고, Traccar 설정이 비었거나 개발용이면 부팅이 실패한다. Solid Queue는 Puma 안에서 구동(`SOLID_QUEUE_IN_PUMA`). 절차는 `docs/deployment.md`. 서버 배포·iOS 실기기 시험은 아직 하지 않았다.

## 알려진 함정

1. **GPS·ETA 없음** — 좌표 저장, 좌표 기반 ETA 계산, `RouteProgress`/`RouteBusSelector`는 재작성(#23)에서 제거됐다. 새 UI가 위치를 보여야 하면 `StopVisit`·`RouteBusStatuses`·`ArrivalPresenter`를 쓴다. 지역(Region/Area) 계층·좋아요·영어 화면도 없다.
2. **이벤트 수신은 항상 200-ack** — 인증 실패(`401`)만 예외. 알 수 없는 단말·지오펜스·운행 없음 등은 `status: ignored` + `reason`으로 200 응답한다. 4xx를 주면 Traccar 포워딩 재시도가 폭주한다(`StopVisitRecorder`).
3. **Route/Stop/Bus 등록은 Traccar 호출과 한 트랜잭션** — Traccar 실패 시 Rails 변경도 취소(`*Registration`, `TraccarRegistration`). 단 **외부 HTTP는 롤백되지 않아** Traccar에만 남는 orphan이 생길 수 있다. 복구는 admin의 `sync_group`/`sync_geofence`/`sync_device`. 운전자의 운행 시작·종료(`Trip*`)는 Traccar를 부르지 않는다. 상세는 `docs/traccar-integration.md`.
4. **운행 중에는 차량의 노선을 바꿀 수 없다**(`Bus#route_unchanged_during_trip`). 노선·정류장·차량에는 `restrict_with_error` 삭제 제약이 있다(배정된 차량이 있는 노선, 방문 기록이 있는 정류장, 운행 기록이 있는 차량은 지울 수 없다).
5. **PIN은 1회용이고 `buses.pin`은 전역 unique** — register API가 PIN만으로 버스를 특정한다. 성공 시 조건부 UPDATE(`pin_registered_at`)로 원자적 소모, IP당 5회 실패 시 15분 잠금(`Rails.cache`). 기기 교체는 admin "PIN 재발급"(`Bus#regenerate_pin!`). PIN은 자동 발급 6자리(검증은 4~6자리 허용), `traccar_unique_id`는 hex 12자.
6. **`deviceId`가 사실상 비밀번호** — 운행 시작·종료 API는 이것만으로 인증한다. 기기별 토큰은 후속 과제(`docs/future-improvements.md` 2번).
7. **운전자가 종료를 누르지 않으면 Trip이 계속 열린다** — 자동 종료 기준은 미정(`docs/policy-draft.md`).
8. **첫 가입자가 자동 operator** — `User#assign_operator_if_first_user`가 `User.count.zero?`로 판정하므로 동시 가입 race가 있고 DB 제약이 없다. 가입 폼은 role을 받지 않는다.
9. **문서 최신성** — 구조나 API 계약이 바뀌면 `docs/traccar-integration.md`, `driver_app/ISSUE.md`, `README.md`, 스킬(`traccar-sync`, `driver-app`), 이 파일의 함정 목록을 같이 고친다. 상세 내용은 이 파일에 복사하지 말고 링크한다.

## 코딩 관례

- 커밋 메시지: `feat:`, `fix:`, `chore:`, `docs:` 접두어 + 한국어 설명.
- UI 문구·주석은 한국어 기본.
- RuboCop omakase 스타일 준수.
