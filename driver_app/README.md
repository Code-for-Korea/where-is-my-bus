# driver_app — 버스 운전자 앱 (Flutter)

[`where-is-my-bus`](../README.md) 모노레포의 일부입니다. 레포 루트는 Rails 웹 앱, 이 폴더는 운전자용 Flutter 앱입니다.

## 역할

- 운전자 단말에서 GPS 위치를 서버로 송신
- 운행 시작·종료를 서버에 알림 (노선은 운전자가 고르지 않고, 관리자가 차량에 배정한 노선으로 운행)
- 서버가 보는 버스 위치(이전·현재·다음 정류장)와 배정 노선을 메인 화면에 표시
- 정류장 크라우드소싱 등록(미구현, `ISSUE.md` 참고)

목업 아티팩트: https://claude.ai/code/artifact/cd691e97-db15-4998-8b02-6f44744d37bd?via=auto_preview

## 위치 송신: Traccar Client SDK

위치 추적 로직을 직접 구현하지 않고 공식 SDK로 UI만 감싼다.

- SDK: [`traccar_client_sdk`](https://pub.dev/packages/traccar_client_sdk) (pub.dev, Apache-2.0) — [traccar.org/traccar-client-sdk](https://www.traccar.org/traccar-client-sdk/) · [Flutter 문서](https://www.traccar.org/traccar-client-sdk-flutter/)
- 역할: 백그라운드 위치 수집 + 권한 요청(위치·배터리 최적화 예외) + OsmAnd 프로토콜(`:5055`)로 서버 전송까지 전부 처리. 앱은 UI(로그인/상태표시/시작·정지)만 구현.
- `serverUrl`/`deviceId`는 온보딩에서 `POST /integrations/traccar/register` 호출로 받은 응답값 사용(`lib/driver_registration.dart`). 설정값·계약 상세는 `ISSUE.md` 참고.
- SDK 범위 밖(직접 구현 필요): 정류장 크라우드소싱 등록 화면.

## 다국어 (한국어/English)

`intl`/ARB 코드생성 대신 record 기반 자체 구현(`lib/l10n/app_strings.dart`) — 2개 언어뿐이라 코드생성 스텝 없는 쪽이 가벼움. 참고: `xenoNote/Dev_knowledge/setup/flutter_app_polish_patterns.md` §10·§11.

- `lib/l10n/language_settings.dart` — 언어 선택을 `SharedPreferences`로 영속화. 저장된 값이 없으면(최초 실행) 시스템 언어를 자동 감지(`ko`→한국어, 그 외 전부→English 폴백).
- `lib/l10n/app_strings.dart` — 화면별 문구를 `(ko:, en:)` record로 정의, `AppStrings.xxx`로 조회.
- 설정화면 "언어" 항목에서 시스템 기본값/한국어/English를 명시적으로 고를 수 있음(고르면 재실행 후에도 유지).
- 언어가 3개 이상으로 늘어나면 표준 `flutter gen-l10n`/ARB 파이프라인으로 전환 검토.

## 개발 체크리스트

설정값·기기별 세부사항·완료/미검증/미구현의 근거는 [`ISSUE.md`](ISSUE.md) 참고.

- [x] 패키지 ID 변경 (`com.tenminutestudio.whereismybusdriver.*`)
- [x] UI 목업 5화면 (`mvp-spec.md`)
- [x] 다국어(한국어/English) 인프라
- [x] iOS `Info.plist` 위치 권한 문구 + 언어별 `InfoPlist.strings` + Background Modes
- [x] Traccar Client SDK 연동(`init`/`start`/`stop`, 상태표시) — 실기기 검증 완료
- [x] 백엔드 API(register/bus/trips start·end) — Rails 쪽 구현 완료. 옛 `positions`·`routes`는 폐지(위치는 Traccar로 직접 전송, 노선은 차량에 배정)
- [x] 서버 운행 시작·종료 연동, 배정 노선·이전/현재/다음 정류장 표시, 앱 재시작 시 위치 전송 자동 재개 (단위·위젯 테스트 통과)
- [ ] iOS 시뮬레이터 e2e 시험 (아래 "iOS 시뮬레이터로 e2e 확인하기")
- [ ] 실기기 e2e 시험 (iOS는 배포 서버 주소를 `Info.plist` 평문 HTTP 예외에 등록해야 함)
- [x] 차량 등록 시 Traccar device 자동 프로비저닝
- [x] register PIN 1회용 처리(유출 대응) — 상세는 `ISSUE.md` 참고
- [x] 설정화면 "PIN으로 재등록" 연결
- [ ] 정류장 크라우드소싱 등록 화면
- [ ] 앱 아이콘/스플래시 이미지 자산 (패키지 ID는 이미 변경됨 — 아이콘은 아직 기본 Flutter 로고)
- [ ] Firebase 연동 시 새 패키지 ID로 `google-services.json` / `GoogleService-Info.plist` 재발급
- [ ] 앱스토어/플레이스토어 배포 파이프라인 (Android 릴리즈 키스토어 포함, 전체 미구성)

## iOS 시뮬레이터로 e2e 확인하기

Mac의 iOS 시뮬레이터는 PC와 네트워크를 공유하므로 `localhost`로 Docker 서버에 바로 붙는다.

1. **서버 실행**: 저장소 루트에서 `docker compose up -d`. 호스트 3000번이 이미 쓰이면 `RAILS_PORT=3300 docker compose up -d`(아래 주소의 3000을 그 포트로 바꿔 읽는다). 첫 기동이면 시드가 차량 2대(1번 → 1번 노선, 2번 → 2번 노선)를 만든다.
2. **PIN 확인**: `docker compose exec rails bin/rails db:seed`가 차량별 PIN을 출력한다. 이미 쓴 PIN이면 관리자 화면(`http://localhost:3000/admin`) 차량 상세에서 "PIN 재발급".
3. **시뮬레이터 부팅 후 앱 실행**: Flutter는 *부팅된* 시뮬레이터만 기기로 인식한다. `open -a Simulator`는 앱만 띄우고 특정 기기를 부팅해 주지 않으므로, 기기를 직접 부팅한다.
   ```
   xcrun simctl list devices available        # 기기 이름과 UDID 확인
   xcrun simctl boot <UDID>                   # 예: iPhone 17
   open -a Simulator                          # 부팅된 기기의 창 띄우기
   flutter devices                            # 목록에 iOS 시뮬레이터가 보이는지 확인
   cd driver_app && flutter run -d <UDID>     # 이름보다 UDID가 정확하다 (iPhone 17 / 17e 구분)
   ```
4. **등록**: 서버 주소 `http://localhost:3000` + PIN → "등록하고 시작하기". 메인 화면에 "1번 차량", "배정 노선 · 1번 노선"이 보이면 성공.
5. **운행 시작**: 버튼을 누르고 위치 권한을 "항상 허용"(또는 앱 사용 중 허용). 서버 대시보드 "운행 중인 버스"에 나타난다.
6. **위치 움직이기** (1번 노선, 터미널 100m 전 → 터미널 → 시장 → 병원 → 고성고 → 80m 뒤):
   ```
   xcrun simctl location booted start --speed=8 --distance=10 \
     34.97246,128.32143 34.9731,128.3222 34.9751,128.3246 34.9771,128.3270 34.9791,128.3294 34.97961,128.33002
   ```
   2번 노선(2번 차량)은 `34.97246,128.32143 34.9731,128.3222 34.9771,128.3270 34.9751,128.3298 34.9731,128.3326 34.9726,128.3333`. 끝나면 `xcrun simctl location booted clear`.
7. **확인**: 앱 메인 화면의 "서버가 보는 위치"(이전·현재·다음, 10초마다 갱신), 관리자 대시보드 "최근 정류장 방문", 승객 화면(`http://localhost:3000`).
8. **종료**: 앱에서 버튼을 눌러 운행 정지 → 대시보드에서 운행이 사라지는지 확인.

시험할 시나리오: ① 정상 등록 ② 운행 시작 후 정류장 순서대로 이동 ③ 운행 종료 ④ 노선이 배정되지 않은 차량으로 시작(관리자 화면에서 배정 해제 후) → 안내 문구 ⑤ 서버를 내린 상태(`docker compose stop rails`)에서 시작·종료 → 상태가 바뀌지 않고 오류 안내 ⑥ 운행 중 앱을 종료했다가 다시 실행 → 위치 전송 자동 재개 ⑦ 관리자가 PIN 재발급 후 앱에서 재등록 ⑧ 정류장을 통과할 때마다 방문이 기록되는지(위치 전송 빈도 점검).

시뮬레이터가 못 보여주는 것: 백그라운드·화면 꺼짐에서의 위치 전송, 배터리, 실제 GPS 정확도. 이 부분은 실기기 시험에서 확인한다.

## Admin 연동

차량을 admin에서 등록하면 Rails가 PIN·`traccar_unique_id`를 자동 생성하고 Traccar 서버에 device도 자동 프로비저닝한다. 운영자는 발급된 PIN과 서버 주소만 운전자에게 전달하면 되고, 절차 안내는 Admin "신규등록 운영자 지침" 페이지(`/admin/guides/bus_registration`)에 있다. PIN은 1회용(최초 등록 시 소모)이라 유출돼도 다른 기기가 같은 PIN으로 추가 등록할 수 없으며, 기기분실/교체 시엔 어드민 차량 상세화면에서 PIN 재발급으로 대응한다 — 상세는 `ISSUE.md` 참고.

## 메타

| 항목 | 값 |
|---|---|
| 패키지명 (pubspec) | `whereismybusapp` |
| Android applicationId | `com.tenminutestudio.whereismybusdriver.AOS` |
| iOS bundle ID | `com.tenminutestudio.whereismybusdriver.iOS` |
| 지원 플랫폼 | iOS, Android |

## 개발

```bash
cd driver_app
flutter pub get
flutter run
```

[Flutter SDK](https://docs.flutter.dev/get-started/install) 필요. Windows 빌드 시 알려진 이슈는 `ISSUE.md` 참고.

## CI / 배포

- 레포 루트 CI(`.github/workflows/ci.yml`)는 Rails 전용이며 `driver_app/**` 변경은 무시합니다. Flutter용 CI 잡은 아직 없습니다.
- Rails 배포 이미지(Kamal)에는 포함되지 않습니다 (`.dockerignore`에서 제외).
- 앱 스토어 배포 파이프라인은 미구성.
