# 내 버스는 언제 올까?

BIS(버스정보시스템)에 등록되지 않은 시골·도서 지역의 노선버스 위치를 시민에게 알려주는 서비스입니다.
버스가 언제 올지 막연히 기다려야 하는 시골버스의 불편함을 해결하는 것을 목표로 합니다.

> Code for Korea 프로젝트

이 저장소는 **웹 애플리케이션(Rails)** 입니다. 버스 운전자용 **iOS 앱**은 별도 저장소로 구성됩니다.

---

## 구성 요소

| 대상 | 영역 | 설명 |
|---|---|---|
| 시민 | `/service` | 지역·노선 선택 후 버스 실시간 위치·도착예정·정류장 확인 |
| 운영자 | `/admin` | 지역/노선/정류장/차량(번호판·PIN) 관리 |
| 운전자 | iOS 앱(별도) | GPS 위치 송신, 정류장 크라우드소싱 등록 |

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
cd web
bundle install
bin/rails db:prepare   # 스키마 생성 + 시드(통영시 욕지도 35번 등)
bin/dev                # 서버 + Tailwind watch 동시 실행
```

접속:

- 시민 서비스: <http://localhost:3000/service>
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

- ✅ 도메인 모델, 관리자 CRUD, 인증·권한, 시민 서비스 화면, 좋아요(추천)
- ⬜ 운전자 iOS 앱용 API
- ⬜ 실시간 버스 위치(운전자 GPS → Solid Cable 브로드캐스트)
- ⬜ 비밀번호 재설정 메일 발송 설정(SMTP / 개발용 letter_opener)

> 현재 `/routes/:id`의 "n정거장 전 · 약 20분 후 도착예정"은 더미 값이며, 화면에 예시임을 명시하고 있습니다.

---

## 개발 메모

- 테스트는 `--skip-test`로 생략된 상태(추후 RSpec 등 선택 도입 가능)
- 관리자 영역은 `Admin::BaseController`에서 운영자 권한을 강제
