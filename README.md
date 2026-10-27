# 내 버스는 언제 올까?

BIS(버스정보시스템)에 등록되지 않은 시골·도서 지역의 노선버스 위치를 시민에게 알려주는 서비스입니다.
버스가 언제 올지 막연히 기다려야 하는 시골버스의 불편함을 해결하는 것을 목표로 합니다.

> Code for Korea 프로젝트

이 저장소는 모노레포입니다. 루트는 **웹 애플리케이션(Rails)**, `driver_app/`은 버스 운전자용 **Flutter 앱**입니다.

## 어떻게 동작하나

GPS 좌표를 쌓아 두고 가까운 정류장을 계산하는 방식이 아니라, **정류장에 들어가고 나갈 때 [Traccar](https://www.traccar.org/)가 알려 주는 Geofence 이벤트를 기록**해서 "버스가 지금 어느 정류장에 있는지"를 알려 줍니다. Rails는 GPS 좌표를 저장하지 않습니다.

```
관리자 ── 정류장·노선 등록, 차량에 노선 배정 ──▶ Rails ──▶ Traccar (정류장 영역·노선 그룹·기기 생성)
운전자 앱 ── 운행 시작·종료 ──▶ Rails
운전자 앱 ── 위치(OsmAnd) ──▶ Traccar ── 정류장 영역 진입/이탈 이벤트 ──▶ Rails (방문 기록) ──▶ 승객 화면
```

- 설계 결정과 근거: [docs/design-event-driven-rewrite.md](docs/design-event-driven-rewrite.md)
- Traccar 연동 상세(자원 대응·이벤트 흐름·설정·보안): [docs/traccar-integration.md](docs/traccar-integration.md)
- 데이터 모델이 왜 이렇게 바뀌었나: [docs/data-model-rewrite.md](docs/data-model-rewrite.md), ERD: [docs/erd.md](docs/erd.md)
- 제품 요구사항·정책 초안·남은 과제: [docs/product_requirements.md](docs/product_requirements.md), [docs/policy-draft.md](docs/policy-draft.md), [docs/future-improvements.md](docs/future-improvements.md)

---

## 구성 요소

| 대상 | 영역 | 설명 |
|---|---|---|
| 승객 | `/` | 정류장을 고르고(필요하면 노선을 골라) 그 노선 버스가 어느 정류장에 있는지 확인 (5초마다 갱신) |
| 운영자 | `/admin` | 노선·정류장·차량 관리, 차량에 노선 배정, 노선에 정류장 추가, 대시보드(운행 중인 버스·최근 정류장 방문) |
| 운전자 | `driver_app/` (Flutter) | PIN으로 기기 등록, 운행 시작·종료, 위치를 Traccar로 전송, 이전·현재·다음 정류장 표시 |

승객 화면은 **정류장 단위**로 알려 줍니다("N정거장 전에 있습니다", "○○ 정차 중"). 좌표 기반 도착 예정 시간(ETA)은 제공하지 않습니다.

---

## 기술 스택

- **Ruby** 4.0.9 / **Rails** 8.1 (`.tool-versions`로 asdf 고정)
- **DB**: SQLite (운영도 파일 DB)
- **프론트**: Hotwire(Turbo/Stimulus) + importmap, **Tailwind CSS 4**
- **인증**: Rails 8 내장 인증(세션 + `has_secure_password`)
- 백그라운드/캐시/케이블: Solid Queue / Solid Cache / Solid Cable
- 위치 서버: Traccar (Docker, `compose.yaml`)
- 배포: Kamal (`config/deploy.yml`은 아직 placeholder)

---

## 도메인 모델

```
Route (노선) ─< RouteStop >─ Stop (정류장)     정류장은 독립된 장소, 여러 노선이 공유
Route ─< Bus (차량)                             차량 1대에 노선 1개를 관리자가 배정 (buses.route_id)
Bus ─< Trip (운행) ─< StopVisit >─ Stop          운전자가 시작·종료, 버스당 진행 중인 운행 1개
User ─< Session                                  role: member / operator — 첫 가입자는 자동으로 operator
```

테이블은 8개(`buses`, `routes`, `route_stops`, `stops`, `stop_visits`, `trips`, `users`, `sessions`)입니다. 시·도/운행지역 계층, 좋아요, 영어 화면, GPS 로그, 좌표 기반 ETA는 요구사항에 없거나 새 구조와 맞지 않아 뺐습니다(다시 넣을지는 팀 논의 대상 — [docs/team-discussion-agenda.md](docs/team-discussion-agenda.md)).

---

## 시작하기

### 가장 쉬운 방법: Docker (Rails + Traccar)

Docker Desktop이 있으면 한 번에 실행됩니다. 처음 기동 때 시드가 실행되어 정류장 6개, 노선 2개, 차량 2대가 만들어지고 Traccar에도 같은 자원이 생깁니다.

```bash
docker compose up -d --build
docker compose exec rails bin/rails "demo:drive[1번]"   # 폰 없이 버스 한 대를 운행시키는 시뮬레이터
```

- 승객 화면 <http://localhost:3000/> · 관리자 <http://localhost:3000/admin> · Traccar <http://localhost:8082>
- 관리자 계정과 차량 PIN·`deviceId`는 `docker compose logs rails`에 출력됩니다.
- 자세한 시연 순서·문제 해결: [docs/local-demo.md](docs/local-demo.md)

### Rails를 직접 실행

사전 준비: [asdf](https://asdf-vm.com/)로 Ruby 4.0.9 설치(`.tool-versions` 참고)

```bash
bundle install
bin/dev            # Rails 서버 + Tailwind watch (Traccar는 포함되지 않음)
```

노선·정류장·차량을 등록하거나 시드(`bin/rails db:prepare`)를 실행하려면 **Traccar 서버가 떠 있어야** 합니다(등록이 Traccar 호출과 한 트랜잭션으로 묶여 있음). Traccar 접속 정보는 환경변수(`TRACCAR_API_BASE_URL`, `TRACCAR_API_TOKEN`, `TRACCAR_INGEST_TOKEN`, `TRACCAR_SERVER_URL`)가 credentials보다 우선하며, 표와 설정 방법은 [docs/traccar-integration.md](docs/traccar-integration.md)에 있습니다. 가장 간단한 방법은 `docker compose up -d traccar`로 Traccar만 띄우는 것입니다.

- 회원가입: <http://localhost:3000/registration/new> — **첫 가입자가 운영자**가 됩니다
- 로컬 개발 DB를 이전 구조에서 가져왔다면 `bin/rails db:reset`이 필요합니다.

### 운전자 앱

[Flutter SDK](https://docs.flutter.dev/get-started/install) 설치 후:

```bash
cd driver_app && flutter pub get && flutter run
```

번들 ID — Android `com.tenminutestudio.whereismybusdriver.AOS` / iOS `com.tenminutestudio.whereismybusdriver.iOS`. 서버 주소 설정과 iOS 시뮬레이터 시험 절차는 [driver_app/README.md](driver_app/README.md)를 참고하세요.

---

## 주요 경로

| 경로 | 설명 |
|---|---|
| `/` | 승객 첫 화면 (정류장 선택) |
| `/stops/:id` | 정류장에 서는 노선 선택 (정류장 QR이 가리키는 주소) |
| `/stops/:stop_id/routes/:route_id` | 그 정류장에서 본 노선 버스 위치 (`/status`가 5초 폴링용 응답, `/detail`이 자세히 보기) |
| `/about` | 서비스 소개 |
| `/admin` | 운영자 대시보드 및 관리 (노선·정류장·차량, 노선 배정, 운영자 지침) |
| `/registration/new`, `/session/new` | 가입 / 로그인 |
| `POST /integrations/traccar/register` | 운전자 앱: PIN으로 기기 등록 (1회용 PIN) |
| `GET /integrations/traccar/bus` | 운전자 앱: 차량·배정 노선·진행 중인 운행 조회 |
| `POST /integrations/traccar/trips/start`, `.../trips/end` | 운전자 앱: 운행 시작·종료 |
| `POST /integrations/traccar/events` | Traccar가 Geofence 이벤트를 포워딩하는 수신 엔드포인트 (`X-Ingest-Token` 인증) |

---

## 개발 명령

```bash
bin/rails test        # 테스트 (Minitest, 전체)
bin/ci                # rubocop + gem/importmap audit + brakeman (CI와 같은 구성)
bin/rubocop           # 스타일
```

- ⚠️ **GitHub Actions CI에는 테스트 잡이 없습니다** — rubocop / brakeman / bundler-audit / importmap audit만 돕니다. 테스트는 로컬에서 직접 실행해 주세요. `driver_app`은 CI가 무시하므로 `flutter analyze`·`flutter test`도 로컬에서 실행해야 합니다.
- 관리자 영역은 `Admin::BaseController`에서 운영자 권한을 강제합니다.
- AI 코딩 에이전트용 프로젝트 가이드는 [AGENTS.md](AGENTS.md)에 있습니다.

---

## 현재 상태 / 다음 단계

- ✅ 데이터 모델·관리자 화면·승객 화면·운전자 앱 API를 Geofence 이벤트 기반으로 재작성
- ✅ 로컬 데모(Docker Compose + 시뮬레이터)와 시뮬레이터 위치 전송 시험(통과 40/40, [docs/location-sampling-test.md](docs/location-sampling-test.md))
- ✅ Android 실기기(Galaxy A51, Android 13)로 폰 → Traccar → Geofence → Rails 방문 기록까지 시험
- ⬜ iOS 실기기 시험, 백그라운드·화면 꺼짐·배터리·GPS 오차 검증
- ⬜ 운영 배포(Kamal 설정 확정), 운영 주소·https 설정
- ⬜ Trip 자동 종료 — 운전자가 종료를 누르지 않으면 운행이 열린 채 남음 ([docs/future-improvements.md](docs/future-improvements.md) 3번)
- ⬜ 운행 시작·종료 API 인증 강화 — 현재는 `deviceId`만으로 인증 (같은 문서 2번)
- ⬜ 운전자 앱: 정류장 크라우드소싱 등록 화면, 앱스토어/플레이스토어 배포 파이프라인
- ⬜ 비밀번호 재설정 메일 발송 설정(SMTP / 개발용 letter_opener)

⚠️ **임시 설정 남아있음** — Android cleartext 예외(`network_security_config.xml`)와 운전자 앱에 내려주는 Traccar 서버 주소(`TRACCAR_SERVER_URL`) 기본값이 로컬 개발용입니다. 실배포 서버 주소가 확정되면 원복·교체가 필요합니다 — 전체 목록은 [`driver_app/ISSUE.md`](driver_app/ISSUE.md) 상단 "임시 설정 (원복 필요)" 섹션을 참고하세요.

---

## 주요 변경 이력

날짜별 전체 이력은 `git log`와 PR에서 볼 수 있고, 여기에는 구조나 운영에 영향을 준 변경만 적습니다. 이후 변경으로 대체된 항목은 그렇게 표시합니다.

### 2026-10-27 — Geofence 이벤트 기반으로 재작성 (#23)

- 데이터 모델을 12개 테이블에서 8개로 줄이고, "GPS 좌표 누적 + 가까운 정류장 계산"을 "Geofence 진입/이탈 이벤트를 `stop_visits`에 기록"으로 바꿈. 정류장이 노선에서 독립되어 여러 노선이 공유하고, 차량에 노선을 하나 배정하며, 운행(Trip)은 운전자가 시작·종료함 ([docs/data-model-rewrite.md](docs/data-model-rewrite.md))
- 운전자 앱 API 변경(**이전 버전과 호환되지 않음**): `positions`·`routes` 제거, `bus`·`trips/start`·`trips/end`·`events` 추가, `register`는 유지하되 응답 변경
- 제거: 시·도/운행지역 계층, 좋아요, 영어 화면, 좌표 기반 ETA, GPS 로그 (GA4도 함께 삭제됐으나 복원 진행 중, 아래 참고)
- ⚠️ **GA4 추적 코드가 삭제돼 복원 중. 복원이 머지되기 전에 운영에 배포하면 방문·이벤트가 수집되지 않음.** 6단계 "승객 화면" 커밋 `6609fa5`(2026-10-23)에서 `layouts/service.html.erb`의 gtag 스크립트와 `app/javascript/ga4.js`가 함께 삭제됐고, 이후 복원되지 않았음. 의도한 삭제가 아니었고("요구사항 구현에 필요한 최소 기능만 남기려던 것", hye-k, PR #20 코멘트) 복원하기로 함 — `feat/restore-ga4`. 원래 코드는 `e92b1c3`(2026-06-26, "SEO 메타태그, GA4 추적 코드 및 이벤트 설정")에서 추가됐으며 `git show 6609fa5^:app/views/layouts/service.html.erb`로 볼 수 있음. 경위와 복원 범위는 [docs/future-improvements.md](docs/future-improvements.md))
- 이 PR에서 CI도 정리: Ruby 4.0.9, gem 보안 업데이트(`net-ssh`, `crass` 등), brakeman 8.1.0

### 2026-09-18 — 차량 등록·PIN 보안 (#17, #18, #19)

- 정류장 등록 시 Traccar geofence 자동 생성, 차량 등록 시 Traccar device 자동 프로비저닝. 노선은 Traccar group, 정류장 연결은 group 단위로 함 (2026-10-27 재작성에서 노선 배정 방식은 바뀌었으나 자원 대응은 유지 — [docs/traccar-integration.md](docs/traccar-integration.md))
- register PIN을 **1회용**으로 처리(유출돼도 같은 PIN으로 다른 기기가 추가 등록할 수 없음)하고 동시 요청 경쟁 상태를 방지함
- 차량 등록 시 Traccar 연동 실패로 롤백되면 재시도가 막히던 버그 수정

### 2026-09-16 — 관리자 화면

- 차량 PIN·`traccar_unique_id` 자동 생성, PIN 재발급 버튼(유출 대응, 재발급하면 기존 PIN 즉시 무효화)
- 차량 목록에서 PIN 컬럼 제거(보안) — 상세 화면에서만 노출
- "신규등록 운영자 지침" 페이지 추가
- 노선·정류장·차량 화면에 최종수정일자 표시 (당시 있던 시·도/운행지역 화면의 표시는 재작성에서 화면과 함께 삭제됨)

---

## License & Open Source Acknowledgments

- This project is licensed under the **Apache License 2.0** - see the [LICENSE.txt](LICENSE.txt) file for details.
- This project utilizes **Traccar**, which is also licensed under the **Apache License 2.0**. For more information, please visit [Traccar Official Website](https://www.traccar.org/).
