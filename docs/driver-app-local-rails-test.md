# driver_app과 로컬 Rails 서버 연결 테스트

이 문서는 Traccar 서버 없이 `driver_app`이 로컬 Rails 서버에 GPS를 직접 전송할 수 있는지 확인하는 방법을 설명한다.

현재 `driver_app`은 위치 수집과 전송을 `traccar_client_sdk`에 위임한다. SDK는 `serverUrl`로 `POST` 요청을 보내므로, Rails가 SDK가 사용하는 OsmAnd 형식의 요청을 직접 받을 수 있으면 단일 서버 구성이 가능하다.

## 브라우저에서 확인할 수 있는 범위

`driver_app`은 Flutter 앱이므로 다음 명령으로 웹 실행을 시도할 수 있다.

```bash
cd driver_app
flutter config --enable-web
flutter pub get
flutter run -d chrome
```

다만 이 프로젝트의 지원 대상은 Android와 iOS이며, 위치 수집·전송은 네이티브 기능을 사용하는 `traccar_client_sdk`에 의존한다. 따라서 Chrome 실행이 되더라도 다음 기능을 브라우저에서 실제 앱과 같은 방식으로 검증할 수 있다고 보장할 수 없다.

- GPS 권한 요청과 실제 위치 수집
- 백그라운드 위치 전송
- Android 알림·배터리 최적화 처리
- SDK의 `init`·`start`·`stop` 동작
- `adb emu geo fix`를 이용한 위치 주입

브라우저 실행은 온보딩 화면, 서버 주소 입력, PIN 등록 요청, Rails 응답에 따른 화면 전환 같은 UI와 API 계약을 빠르게 확인하는 용도로만 사용한다. `traccar_client_sdk`가 웹 플랫폼을 지원하지 않으면 웹 빌드 자체가 실패할 수 있으며, 이 경우 앱 코드의 문제가 아니라 SDK의 플랫폼 지원 범위 문제일 수 있다.

Rails를 브라우저에서 여는 것과 `driver_app`을 Chrome에서 실행하는 것은 별개의 테스트다. Rails 브라우저 화면은 승객·관리자 웹을 확인하고, driver_app 웹 실행은 운전자 앱 UI를 확인한다. 어느 쪽도 Android/iOS의 실제 GPS 전송을 대신하지 않는다.

브라우저에서 GPS 수신 계약만 확인하려면 앱을 웹으로 억지로 실행하기보다 다음 순서를 사용한다.

1. `curl`로 `POST /gps` 요청을 재현한다.
2. Rails 로그와 `Trip`·`GpsLog`·`CurrentPosition`·`PositionHistory`를 확인한다.
3. 앱 UI와 register/routes 응답만 Chrome에서 확인한다.
4. 실제 위치 권한과 백그라운드 전송은 Android 기기 또는 에뮬레이터에서 확인한다.

## 먼저 확인할 구조

앱은 다음 순서로 동작한다.

1. 앱이 `adminUrl/integrations/traccar/register`에 PIN을 보낸다.
2. Rails가 `traccarServerUrl`과 `deviceId`를 응답한다.
3. 앱이 응답받은 `traccarServerUrl`을 SDK의 `serverUrl`로 사용한다.
4. 운행을 시작하면 SDK가 GPS 위치를 `serverUrl`로 전송한다.

로컬 단일 서버 테스트에서는 두 URL이 다음처럼 될 수 있다.

```text
adminUrl:         http://10.0.2.2:3000
traccarServerUrl: http://10.0.2.2:3000/gps
```

Android 에뮬레이터에서 `10.0.2.2`는 호스트 컴퓨터를 가리킨다. 에뮬레이터에서 `localhost`를 사용하면 에뮬레이터 자신에 접속하므로 Rails 개발 서버에 연결되지 않는다.

## 현재 구현에서 먼저 해결할 사항

SDK가 보내는 실제 요청은 다음 형식이다.

- `POST`
- `application/x-www-form-urlencoded`
- `id`, `lat`, `lon`, `timestamp` 파라미터
- `timestamp`는 epoch 초 단위
- `speed`는 knots 단위

자세한 요청 형식은 [OsmAnd 요청 샘플](osmand-request-samples.md)에 기록되어 있다.

`app/controllers/gps_controller.rb`는 ISO8601 timestamp만 지원하며, 숫자 epoch timestamp는 `501 Not Implemented`로 거부한다. 이 차단은 의도된 동작이다. 실제 SDK는 숫자 epoch timestamp를 보내므로, SDK를 `/gps`에 직접 연결하는 단일 서버 구성은 epoch 초 지원이 추가된 후에 가능하다.

SDK 대신 아래 curl 예제처럼 ISO8601 timestamp를 보내면 GPS 수신 계약을 그대로 확인할 수 있다.

## 1. Rails 서버 실행

먼저 데이터베이스를 준비하고 Rails를 모든 인터페이스에 바인딩한다.

```bash
bin/rails db:prepare
bin/rails server -b 0.0.0.0 -p 3000
```

호스트에서 서버 상태를 확인한다.

```bash
curl -i http://127.0.0.1:3000/up
```

Android 에뮬레이터에서도 확인한다.

```bash
adb shell curl http://10.0.2.2:3000/up
```

두 요청 모두 200이어야 한다.

## 2. 앱 없이 GPS 수신 계약 확인

앱을 실행하기 전에 `/gps` 요청을 `curl`로 재현한다. 실제 SDK는 epoch 초 timestamp를 보내지만 현재 `/gps`는 ISO8601만 받으므로(위 섹션 참고), 여기서는 ISO8601 timestamp를 사용한다.

```bash
curl -i -X POST http://127.0.0.1:3000/gps \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data 'id=goseong-1-demo' \
  --data 'lat=35.2285' \
  --data 'lon=128.8894' \
  --data 'timestamp=2026-10-18T12:00:00Z' \
  --data 'accuracy=5' \
  --data 'speed=0' \
  --data 'bearing=0' \
  --data 'batt=80'
```

요청이 성공하면 다음 항목을 확인한다.

```bash
bin/rails runner 'bus = Bus.find_by!(traccar_unique_id: "goseong-1-demo"); p bus.trips.order(:id).last; p bus.current_position; p bus.position_histories.order(:id).last'
```

확인 대상은 다음과 같다.

- 활성 `Trip` 생성 또는 재사용
- `GpsLog` 저장
- `CurrentPosition` 저장
- `PositionHistory` 저장
- 오래된 timestamp가 `CurrentPosition`을 덮어쓰지 않음

이 단계가 통과하지 않으면 에뮬레이터 테스트를 진행하지 않는다.

## 3. Android 에뮬레이터에서 앱 실행

```bash
cd driver_app
flutter pub get
flutter devices
flutter run -d <emulator-id>
```

앱의 서버 주소에는 다음을 입력한다.

```text
http://10.0.2.2:3000
```

앱이 PIN으로 등록되면 Rails의 `register` 응답에서 `traccarServerUrl`이 로컬 `/gps`를 가리키는지 확인한다. PIN은 1회용이므로 반복 테스트할 때는 관리자 화면에서 PIN을 재발급한다.

앱에서 운행을 시작한 뒤 Rails 로그에서 다음 요청을 찾는다.

```text
POST /gps
```

## 4. 에뮬레이터 위치 주입

Android 에뮬레이터의 위치를 `adb`로 설정할 수 있다.

```bash
adb emu geo fix 128.8894 35.2285
```

인자는 경도, 위도 순서다. 위치 권한을 허용하고 운행을 시작한 뒤, 몇 초 후 Rails 로그와 데이터베이스의 위치가 갱신되는지 확인한다.

SDK의 전송 주기는 현재 30초로 설정되어 있으므로 위치를 주입한 직후가 아니라 다음 전송 주기까지 기다려야 할 수 있다.

## Android 로컬 HTTP 주의사항

Android 앱은 `network_security_config.xml`을 사용하며, 현재는 특정 Traccar 테스트 도메인에 대해서만 평문 HTTP를 허용한다. `http://10.0.2.2:3000`을 사용하려면 개발 테스트용으로 평문 HTTP 허용 범위를 추가해야 할 수 있다.

이 설정은 개발 테스트에만 사용하고, 운영에서는 HTTPS를 사용한다. 기존의 임시 Traccar 도메인 허용 설정을 실배포 설정으로 간주하거나 그대로 확대하지 않는다.

## 실기기에서 테스트하는 경우

실기기는 `10.0.2.2`를 사용할 수 없다. Rails를 `0.0.0.0`에 바인딩하고, 같은 네트워크에 있는 개발 컴퓨터의 사설 IP를 사용한다.

```text
http://192.168.x.x:3000
```

개발 컴퓨터의 방화벽과 공유기 격리 설정 때문에 연결이 막힐 수 있다. 실기기 테스트에서는 다음 동작도 확인해야 한다.

- 위치 권한 요청 순서
- 백그라운드 위치 전송
- 배터리 최적화 예외
- 화면을 끈 뒤에도 위치 전송이 계속되는지
- 실제 GPS 정확도와 전송 주기

에뮬레이터는 HTTP 계약과 DB 적재 확인에는 충분하지만, 실제 센서와 백그라운드 동작을 완전히 대체하지는 못한다.

## 최종 검증 순서

```text
Rails /up 확인
  ↓
curl로 POST /gps 재현
  ↓
Trip·GpsLog·CurrentPosition·PositionHistory 확인
  ↓
에뮬레이터에서 Rails register 호출
  ↓
register 응답의 traccarServerUrl 확인
  ↓
앱에서 운행 시작
  ↓
adb로 위치 주입
  ↓
Rails 로그와 DB 적재 확인
```

이 절차를 통과하면 Traccar 없이 Rails 단일 서버가 GPS 수신과 저장을 담당할 수 있는지 판단할 수 있다. 단, `/gps`가 현재 토큰 없이 `id`만으로 버스를 식별하므로 운영 전에는 기기별 인증이나 별도 rate limit을 추가로 검토해야 한다.

## 테스트 방법별 판단 기준

| 방법 | 확인할 수 있는 것 | 확인할 수 없는 것 |
| --- | --- | --- |
| Rails 브라우저 | 승객·관리자 웹 화면, 폴링 결과 | driver_app 동작, GPS 권한 |
| `driver_app` Chrome 실행 | 운전자 UI, 일부 register/routes API 흐름 | 네이티브 SDK GPS, 백그라운드 전송 |
| `curl` | Rails의 GPS 요청 형식, 인증·DB 적재 | 앱 UI, 모바일 권한 |
| Android 에뮬레이터 | 앱과 Rails의 HTTP 연동, 모의 위치, 기본 권한 흐름 | 실제 센서, 제조사별 배터리 정책 |
| Android 실기기 | 실제 GPS, 권한, 백그라운드·배터리 동작 | — |
