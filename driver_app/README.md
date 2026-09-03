# driver_app — 버스 운전자 앱 (Flutter)

[`where-is-my-bus`](../README.md) 모노레포의 일부입니다. 레포 루트는 Rails 웹 앱, 이 폴더는 운전자용 Flutter 앱입니다.

## 역할

- 운전자 단말에서 GPS 위치를 서버로 송신
- 정류장 크라우드소싱 등록

현재는 스캐폴드만 있는 상태이며, 그전까지는 공식 Traccar Client 앱으로 위치를 수집합니다 (`../docs/traccar-integration.md`).

## 메타

| 항목 | 값 |
|---|---|
| 패키지명 (pubspec) | `whereismybusapp` |
| Android applicationId | `kr.codefor.whereismybusapp` |
| iOS bundle ID | `kr.codefor.whereismybusapp` |
| 지원 플랫폼 | iOS, Android |

## 개발

```bash
cd driver_app
flutter pub get
flutter run
```

[Flutter SDK](https://docs.flutter.dev/get-started/install) 필요.

## CI / 배포

- 레포 루트 CI(`.github/workflows/ci.yml`)는 Rails 전용이며 `driver_app/**` 변경은 무시합니다. Flutter용 CI 잡은 아직 없습니다.
- Rails 배포 이미지(Kamal)에는 포함되지 않습니다 (`.dockerignore`에서 제외).
- 앱 스토어 배포 파이프라인은 미구성.
