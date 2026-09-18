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

- **Ruby** 4.0.2 / **Rails** 8.1 (`.tool-versions`로 asdf 고정)
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

사전 준비: [asdf](https://asdf-vm.com/)로 Ruby 4.0.2 설치(`.tool-versions` 참고)

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

⚠️ **임시 설정 남아있음** — 내부 테스트 Traccar 서버(비공개 도메인)로 로컬 기본값이 임시 고정돼 있습니다. 실배포 서버 주소 확정되면 원복 필요 — 원복 대상 전체 목록은 [`driver_app/ISSUE.md`](driver_app/ISSUE.md) 상단 "임시 설정 (원복 필요)" 섹션 참고.

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
