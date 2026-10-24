# 내 버스는 언제 올까?

BIS(버스정보시스템)에 등록되지 않은 시골·도서 지역의 노선버스 위치를 시민에게 알려주는 서비스입니다.
버스가 언제 올지 막연히 기다려야 하는 시골버스의 불편함을 해결하는 것을 목표로 합니다.

> Code for Korea 프로젝트

이 저장소는 모노레포입니다. 루트는 **웹 애플리케이션(Rails)**, `driver_app/`은 버스 운전자용 **Flutter 앱**입니다.

---

## 구성 요소

| 대상 | 영역 | 설명 |
|---|---|---|
| 시민 | `/service` | 지역·노선 선택 후 버스 실시간 위치·도착예정·정류장 확인 |
| 운영자 | `/admin` | 지역/노선/정류장/차량(번호판·PIN) 관리 |
| 운전자 | `driver_app/` (Flutter) | GPS 위치 송신, 정류장 크라우드소싱 등록 |

---

## 기술 스택

- **Ruby** 4.0.9 / **Rails** 8.1 (`.tool-versions`로 asdf 고정)
- **DB**: SQLite
- **프론트**: Hotwire(Turbo/Stimulus) + importmap, **Tailwind CSS 4**
- **인증**: Rails 8 내장 인증(세션 + `has_secure_password`)
- 백그라운드/캐시/케이블: Solid Queue / Solid Cache / Solid Cable
- 배포: Kamal (기본 설정 포함)

---

## 도메인 모델

```
Region (시·도)
  └─ Area (운행지역, 예: 통영시 욕지도)
       ├─ Route (노선, 예: 35번 · 배차간격 · 추천수)
       │    └─ Stop (정류장 · 순서 · 좌표)
       └─ Bus (차량 · 번호판 · 인증 PIN)

User (member / operator)  — 첫 가입자는 자동으로 operator
```

- 카운터 캐시: `areas_count`, `routes_count`, `stops_count`
- 정류장 좌표는 운전자 앱의 크라우드소싱으로 채워질 예정(미등록 표시 지원)

---

## 시작하기

사전 준비: [asdf](https://asdf-vm.com/)로 Ruby 4.0.9 설치(`.tool-versions` 참고)

```bash
bundle install
bin/rails db:prepare   # 스키마 생성 + 시드(통영시 욕지도 35번 등)
bin/dev                # 서버 + Tailwind watch 동시 실행
```

운전자 앱(`driver_app/`): [Flutter SDK](https://docs.flutter.dev/get-started/install) 설치 후 `cd driver_app && flutter pub get && flutter run`. 번들 ID — Android `com.tenminutestudio.whereismybusdriver.AOS` / iOS `com.tenminutestudio.whereismybusdriver.iOS`.

접속:

- 시민 서비스: <http://localhost:3000/>
- 회원가입: <http://localhost:3000/registration/new> — **첫 가입자가 운영자**가 됩니다
- 관리자: <http://localhost:3000/admin> (운영자 로그인 필요)

### 로컬 Traccar 서버

Traccar 연동(admin 동기화, 위치 포워딩, 운전자 앱 등록)을 내부 테스트 서버 없이 로컬에서 확인하려면 Traccar를 Docker로 띄웁니다. 사전 준비: Docker Desktop, `curl`.

```
폰/시뮬레이터 ─▶ :5055 (OsmAnd) ─▶ Traccar ─ 포워딩 ─▶ Rails /integrations/traccar/positions
                                       ▲
                Rails admin CRUD ─ :8082 (REST API)
```

```bash
bin/dev                                              # Rails + Tailwind + 로컬 Traccar(Docker)를 함께 실행, 종료하면 Traccar도 정지
# admin에서 지역·운행지역·노선·정류장·버스 등록 후 배차
bin/traccar-bus --device <버스의 traccar_unique_id>   # 가짜 버스 위치 전송
```

`bin/dev`는 `Procfile.dev`의 `traccar` 프로세스(`bin/traccar dev`)로 Traccar를 띄웁니다. Docker를 쓸 수 없으면 경고만 하고 Rails는 그대로 실행되며, Traccar가 필요 없으면 `TRACCAR=0 bin/dev`로 건너뜁니다. 환경변수·`.env` 설정은 필요 없습니다(아래 기본값 참고).

| 명령 | 설명 |
|---|---|
| `bin/traccar [up]` | Traccar만 따로 기동(이미 있으면 재시작). `traccar.xml`을 매번 새로 생성 |
| `bin/traccar down` / `status` / `logs` | 정지·삭제(데이터 유지) / 상태 / 로그 |
| `bin/traccar reset` | 컨테이너와 데이터 삭제 후 재기동 |
| `bin/traccar dev` | `Procfile.dev`용 foreground 모드(기동 → 로그 → 종료 시 정지) |
| `bin/traccar-bus` | 배차된 노선의 정류장 좌표를 따라 이동하며 :5055로 OsmAnd 요청 전송 (`--loop`, `--interval`, `--steps`, `--route "lat,lng;…"`) |

| 항목 | 값 |
|---|---|
| Traccar 콘솔·API | <http://localhost:8082> (`admin@localbus.test` / `localbus`) |
| 위치 수신(OsmAnd) | `http://localhost:5055` |
| 포워딩 대상 | `http://host.docker.internal:3000/integrations/traccar/positions` (`X-Ingest-Token: dev-traccar-token`) |
| 데이터 | `tmp/docker/volumes/traccar/` (내장 H2 파일 DB — SQLite 아님, git 제외) |
| 이미지 | `traccar/traccar:6.14.4` — 내부 테스트 서버와 같은 버전(`TRACCAR_IMAGE`로 변경) |

- **Rails 설정은 개발 기본값으로 동작**합니다(`config/traccar.yml`, 환경별 규칙은 [`docs/traccar-integration.md`](docs/traccar-integration.md#traccar-설정-configtraccaryml)): `api_base_url` `http://localhost:8082`, 관리자 `admin@localbus.test`/`localbus`, `server_url` `http://localhost:5055`, `ingest_token` `dev-traccar-token`. `bin/traccar`와 같은 값이므로 한쪽을 바꾸면 둘 다 바꿉니다. 같은 이름의 ENV(`TRACCAR_API_BASE_URL`/`TRACCAR_API_EMAIL`/`TRACCAR_API_PASSWORD`/`TRACCAR_SERVER_URL`/`TRACCAR_INGEST_TOKEN`)로 덮어쓸 수 있습니다.
- **로컬(development/test)은 Rails credentials를 읽지 않습니다.** 외부 서버 값이 credentials에 있어도 로컬 작업이 외부 서버를 건드리지 않습니다. 운영은 credentials → ENV 순서이고 기본값이 없습니다. test 환경에는 개발 기본값이 없어서 테스트가 로컬 Traccar에 접속하지 않습니다.
- Traccar 컨테이너가 호스트의 Rails로 포워딩할 수 있도록 `bin/dev`가 Docker가 있을 때 `BINDING=0.0.0.0`으로 서버를 띄우고, `development.rb`가 `host.docker.internal` 호스트를 허용합니다. 이 때문에 개발 서버가 같은 네트워크에 열립니다. Traccar를 쓰지 않으면 `TRACCAR=0 bin/dev`로 기본 바인딩(로컬호스트)을 유지하세요.
- 포워딩 포트는 `bin/dev`의 `PORT`(기본 3000)를 따릅니다(`RAILS_PORT`로 전달). `bin/traccar up`을 따로 쓸 때 Rails 포트가 다르면 `PORT=3001 bin/traccar up`으로 기동하세요.
- 운전자 앱(`driver_app/`): 에뮬레이터는 호스트가 `10.0.2.2`이므로 `TRACCAR_SERVER_URL=http://10.0.2.2:5055 bin/dev`로 Rails를 띄우고 앱의 서버 주소도 `http://10.0.2.2:3000`을 씁니다. 실기기는 PC의 LAN IP를 씁니다. cleartext(http) 허용 설정은 `driver_app/ISSUE.md` 참고.
- `bin/traccar reset`으로 Traccar 데이터를 지우면 Rails에 저장된 `traccar_group_id`/`traccar_geofence_id`/`traccar_device_id`가 어긋납니다. 로컬 DB도 함께 초기화(`bin/rails db:reset`)하세요.

<details>
<summary>문제 해결</summary>

- `Docker 데몬에 연결할 수 없습니다` — Docker Desktop을 실행하거나 재시작하세요.
- Traccar 로그(`bin/traccar logs`)에 `Position forwarding failed` — `403`은 호스트 차단(`config.hosts`의 `host.docker.internal`), `404`는 `forward.type` 설정 문제, 연결 거부는 Rails가 `0.0.0.0`에 바인딩되지 않았거나(`bin/dev`로 실행했는지, `TRACCAR=0`이 아닌지) 포워딩 포트가 다른 경우입니다.
- 포워딩이 `401`(Rails 로그) — Traccar의 `X-Ingest-Token`과 Rails `TRACCAR_INGEST_TOKEN`이 다릅니다. `TRACCAR_INGEST_TOKEN` ENV를 따로 설정하지 않았는지 확인하세요.
- admin에서 버스·노선 등록이 `422` — 로컬 Traccar가 떠 있는지(`bin/traccar status`), `TRACCAR_API_*` ENV를 따로 설정했다면 값이 맞는지 확인하세요.
- 위치가 승객 화면에 안 나옴 — Traccar 콘솔 Devices에 버스의 `traccar_unique_id`가 있는지, 시뮬레이터의 `--device` 값이 같은지 확인하세요. seed 버스(`goseong-1-demo`)는 admin에서 단말 동기화를 해야 Traccar에 생깁니다.
- 포트 충돌 — `bin/traccar`가 8082/5055를 쓰는 다른 컨테이너는 정지시킵니다. 컨테이너가 아닌 프로세스가 점유 중이면 `lsof -i :8082`로 확인하세요.
- 로그 — `bin/traccar logs`, 또는 `tmp/docker/volumes/traccar/logs/`.

</details>

---

## 주요 경로

| 경로 | 설명 |
|---|---|
| `/` | 랜딩(로그인 상태 표시) |
| `/service` | 시민 서비스 스플래시 |
| `/service/select` | 지역→운행지역→노선 캐스케이딩 선택 |
| `/routes/:id` | 노선 실시간 위치(※ 위치값은 운전자 앱 연동 전까지 예시) |
| `/routes/:id/stops` | 노선 정류장 목록 + 현재 위치 |
| `/admin` | 운영자 대시보드 및 관리 |
| `/registration/new`, `/session/new` | 가입 / 로그인 |

---

## 현재 상태 / 다음 단계

- ✅ 도메인 모델, 관리자 CRUD, 인증·권한
- ✅ 승객서비스 웹화면(mvp 기준 완료), 좋아요(추천)
- ✅ 운전자 앱(`driver_app/` Flutter) — Traccar Client SDK 연동(GPS 전송) + register/routes API 실연동. 실서버+실기기 e2e 검증 완료(아래 "어드민 변경" 참고)
- ✅ 실시간 버스 위치 — 운전자 GPS → Traccar 서버 → Rails 수신(`/integrations/traccar/positions`) → 기존 폴링(5초)으로 시민 화면 반영. Solid Cable 도입은 보류 결정(`docs/traccar-integration.md`)
- ✅ 차량 등록 시 Traccar 디바이스 자동 프로비저닝(`docs/traccar-integration.md` 로드맵 2단계)
- ⬜ 운전자 앱: 정류장 크라우드소싱 등록 화면, 앱스토어/플레이스토어 배포 파이프라인 (`driver_app/README.md` 체크리스트 참고)
- ⬜ Trip 자동 종료(오프라인/타임아웃, Solid Queue) — `docs/traccar-integration.md` 로드맵 3단계
- ⬜ 비밀번호 재설정 메일 발송 설정(SMTP / 개발용 letter_opener)

### 어드민 변경 (2026-09-16)

- 차량 PIN·`traccar_unique_id` 자동 생성 + PIN 재발급 버튼(유출 대응, 재발급 시 기존 PIN 즉시 무효화)
- 차량 목록에서 PIN 컬럼 제거(보안) — 상세화면에서만 노출
- Admin "신규등록 운영자 지침" 페이지 추가
- 시·도/운행지역/노선/정류장/차량 리스트·상세에 최종수정일자 표시

### 어드민 변경 (2026-09-18)

- 차량 등록 시 Traccar device 자동 프로비저닝, driver_app register API 실연동 활성화(실서버 e2e 검증 완료)
- register PIN을 1회용으로 처리(유출돼도 같은 PIN으로 다른 기기가 추가 등록 불가) + 동시 요청 경쟁 상태 방지
- admin 차량 등록 시 Traccar 연동 실패로 롤백되면 재시도가 막히던 버그 수정

⚠️ **임시 설정 남아있음** — 운전자 앱(Android)의 cleartext(HTTP) 허용이 내부 테스트 서버 도메인에만 걸려 있습니다. 실배포 서버 주소 확정되면 원복 필요 — 원복 대상은 [`driver_app/ISSUE.md`](driver_app/ISSUE.md) 상단 "임시 설정 (원복 필요)" 섹션 참고. (Rails의 `traccar_server_url` 개발 기본값은 로컬 Traccar(`http://localhost:5055`)로 바뀌어 더 이상 내부 서버에 고정돼 있지 않습니다.)

---

## Google Analytics 4 (by xeno)

**Measurement ID**: `G-V5FQ7DHE99`
production 환경에서만 로드 (`Rails.env.production?` 조건).

### 페이지 경로 정의
GA4 "페이지 및 화면" 리포트에는 실제 URL 대신 의미있는 가상 경로로 기록됩니다.

| 페이지 | 실제 URL | GA4 page_path |
|--------|----------|---------------|
| 홈 | `/` | `/` |
| 소개 | `/about` | `/about` |
| 정류장 도착 | `/r/:region_slug/:stop_id` | `/:지역명/:버스번호/:정류장명` |

예) `/r/goseong/3` → `/경남고성/1번/거류면사무소`

### 이벤트 정의

| 이벤트 | 발생 시점 | 파라미터 |
|--------|-----------|---------|
| `arrival_status` | 정류장 페이지 첫 폴링 응답 | `status`, `stop_name`, `bus_number` |
| `like_stop` | 좋아요 버튼 클릭 | `stop_name`, `bus_number` |
| `select_bus` | 바텀시트에서 버스 선택 확인 | `region`, `bus_number`, `stop_name` |
| `view_detail` | 자세히보기 클릭 | `stop_name`, `bus_number` |

**`arrival_status` status 값 설명**

| status | 의미 | 분석 활용 |
|--------|------|-----------|
| `running` | 버스 운행 중 + GPS 수신 정상 → 사용자가 실제 도착 정보를 받은 상태 | 서비스 유효 이용률 |
| `no_trip` | 현재 운행 중인 버스 없음 (운행 시간 외 접속) | QR 스티커 위치·운행시간 안내 필요 여부 판단 |
| `no_data` | 버스 운행 중이나 GPS 미수신 | 드라이버 앱 작동 이상 감지 |

### QR vs 직접 접속 구분

QR 스티커 URL에 UTM 파라미터를 추가하면 GA4 트래픽 소스에서 자동 분리됩니다.

```
/r/goseong/3?utm_source=qr&utm_medium=qr_code&utm_campaign=stop_sticker
```

## License & Open Source Acknowledgments

- This project is licensed under the **Apache License 2.0** - see the [LICENSE.txt](LICENSE.txt) file for details.
- This project utilizes **Traccar**, which is also licensed under the **Apache License 2.0**. For more information, please visit [Traccar Official Website](https://www.traccar.org/).

---

## 개발 메모

- 테스트는 `--skip-test`로 생략된 상태(추후 RSpec 등 선택 도입 가능)
- 관리자 영역은 `Admin::BaseController`에서 운영자 권한을 강제
