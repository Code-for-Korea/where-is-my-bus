# driver_app — 버스 운전자 앱 (Flutter)

[`where-is-my-bus`](../README.md) 모노레포의 일부입니다. 레포 루트는 Rails 웹 앱, 이 폴더는 운전자용 Flutter 앱입니다.

## 역할

- 운전자 단말에서 GPS 위치를 서버로 송신
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
- [x] 백엔드 API(register/positions/routes) — Rails 쪽 5개 항목 구현 완료. driver_app 실연동 코드도 작성됐으나 **현재 임시 비활성**(서버 주소 미확정) — `ISSUE.md` "임시 설정" 참고
- [x] 설정화면 "PIN으로 재등록" 연결
- [ ] 정류장 크라우드소싱 등록 화면
- [ ] 앱 아이콘/스플래시 이미지 자산 (패키지 ID는 이미 변경됨 — 아이콘은 아직 기본 Flutter 로고)
- [ ] Firebase 연동 시 새 패키지 ID로 `google-services.json` / `GoogleService-Info.plist` 재발급
- [ ] 앱스토어/플레이스토어 배포 파이프라인 (Android 릴리즈 키스토어 포함, 전체 미구성)

## Admin 연동

버스 등록 → Traccar 서버 등록 절차는 Admin "신규등록 운영자 지침" 페이지(`/admin/guides/bus_registration`)에 실제 문구가 있음. PIN·`traccar_unique_id`는 Rails가 자동 생성하며, PIN은 어드민 차량 상세화면에서 재발급(유출 대응) 가능 — 상세는 `ISSUE.md` 참고.

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
