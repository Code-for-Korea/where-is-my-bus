# 로컬 데모 실행

Rails 앱과 Traccar 서버를 로컬에서 띄우고, 폰 없이 시뮬레이터로 버스 운행을 흉내낸다.
설계 배경은 `docs/design-event-driven-rewrite.md`, 제품 요구사항은 `docs/product_requirements.md`.

## 어떤 방식으로 띄울까

Traccar는 두 방식 모두 **도커 컨테이너**로 돈다(호스트에 직접 설치하는 방식은 지원하지 않는다). 다른 점은 Rails를 어디서 돌리느냐다.

| | A. `docker compose` | B. `bin/dev` |
|---|---|---|
| Rails | 컨테이너 | 내 PC (Ruby 4.0.9 필요) |
| Traccar | 컨테이너(compose 서비스) | 컨테이너 `where-is-my-bus-traccar` |
| 준비물 | Docker Desktop만 | Docker Desktop + Ruby 환경 |
| 데모 시드 | 첫 기동 때 자동 | 직접 `bin/rails demo:seed` |
| 맞는 경우 | 시연, 처음 돌려 보기, Ruby 환경이 없는 사람 | Rails 코드를 계속 고치기, 디버거 사용 |

**두 방식은 같은 포트(8082·5055)를 쓰므로 동시에 띄울 수 없다.** 한쪽을 끄고 다른 쪽을 띄운다. 선택 기준은 한 줄이다: 보여 주거나 처음 돌려 볼 때는 A, 코드를 고칠 때는 B.
운전자 앱 시험에는 어느 쪽이든 된다(Rails API와 Traccar만 있으면 된다).

## A. docker compose로 실행

### 준비물

- Docker Desktop (Compose 포함)
- 포트 `3000`(Rails), `8082`(Traccar 웹·API), `5055`(Traccar 위치 수신)이 비어 있어야 한다. Rails 포트가 이미 쓰이고 있으면 `RAILS_PORT=3300 docker compose up -d`처럼 다른 포트로 띄우고, 아래 주소의 `3000`을 그 포트로 바꿔 읽는다 (문제 해결 참고)

### 실행

```bash
docker compose up -d --build          # 첫 실행은 이미지 빌드와 데모 시드 때문에 몇 분 걸린다
```

첫 기동 때 `bin/docker-dev`가 `db:prepare` 다음에 **`demo:seed`를 실행한다.** 이 태스크는 관리자 계정, 정류장 6개, 노선 2개, 차량 2대를 만들고
**Traccar에도 그룹·Geofence·기기를 만들고, 차량을 노선에 배정해 기기를 그 노선의 그룹에 넣는다**. Traccar가 아직 기동 중이면 잠시 기다렸다가 재시도한다.
차량의 PIN과 `deviceId`, 관리자 로그인 정보는 `docker compose logs rails`에 출력된다.
다시 보고 싶으면 `docker compose exec rails bin/rails demo:seed`를 실행한다 (여러 번 실행해도 안전하다).

| 주소 | 내용 |
|---|---|
| http://localhost:3000 | 승객 화면 |
| http://localhost:3000/admin | 관리자 화면 (시드가 출력한 계정으로 로그인) |
| http://localhost:8082 | Traccar 웹 UI |

## 승객 화면 구성

`origin/main`의 디자인(폰 프레임, 히어로 이미지, 회색 정류장 패널 + 파란 도착 패널, 노선 진행 바, 자세히보기 모달, 바텀시트 선택)을 그대로 따른다. 달라진 점:

- 선택 시트가 "지역 → 노선 → 정류장"이 아니라 **"정류장 → 노선"**이다 (지역 계층이 없다).
- 파란 패널의 큰 글씨가 "약 N분 후 도착예정"(ETA)이 아니라 **"N정거장 전에 있습니다"**다. 진행 바는 남은 정류장 수로 움직인다.
- 좋아요 버튼과 언어 전환(KO/EN)은 없다.
- 정류장에 노선이 하나뿐이면 노선 선택을 건너뛰고, 여러 개면 노선 선택 화면(`/stops/:id`)을 거친다. 정류장 QR은 이 주소를 쓰면 된다.

## 시연 순서

(A·B 공통. B(`bin/dev`)로 띄웠다면 아래 명령의 `docker compose exec rails`를 빼고 `bin/rails ...`로 바로 실행한다.)

1. 승객 화면에서 **고성병원**을 고르고(1번·2번 노선이 함께 선다) **1번 노선**을 연다.
2. 다른 터미널에서 운행을 시뮬레이션한다.

   ```bash
   docker compose exec rails bin/rails "demo:drive[1번]"
   ```

   버스 `1번`이 **배정된 노선(1번 노선)**으로 운행을 시작하고 정류장을 차례로 지나간다 (약 100초). 노선은 고르지 않는다 — 관리자 화면의 노선·차량 배정을 따른다.
   인자는 `demo:drive[버스(번호판 또는 번호),전송간격초,정차초]`이고 뒤의 둘은 생략할 수 있다.
3. 승객 화면이 5초마다 갱신되면서 "위치 확인 중 → 터미널 정차 → 출발 → … → 내 정류장에 정차 중 → 이미 지나갔어요"로 바뀐다.
4. 관리자 대시보드의 "운행 중인 버스"와 "최근 정류장 방문"에서 같은 흐름을 볼 수 있다.
5. `demo:drive[2번]`을 돌리면 2번 버스가 1번 노선의 시장 정류장 영역을 지나가지만 **시장 이벤트는 오지 않는다** (노선별 Traccar 그룹 설계).

## 데이터가 흐르는 길

```
관리자 ── 차량에 노선 배정 ──▶ Rails ── 기기를 노선 그룹으로 이동 ──▶ Traccar   (배정할 때 한 번)
시뮬레이터 ── 운행 시작 API(노선은 배정된 것) ──▶ Rails
     │
     └─ 위치(OsmAnd, :5055) ──▶ Traccar ── Geofence 진입/이탈 이벤트 ──▶ Rails (방문 기록) ──▶ 승객 화면
```

## B. bin/dev로 실행 (코드를 고칠 때)

Rails를 내 PC에서 직접 돌리고 Traccar만 도커로 띄운다. 준비물은 Docker Desktop, Ruby 환경(`.tool-versions`), 비어 있어야 하는 포트 `3000`·`8082`·`5055`다. 위의 비교 표에서 A와 같은 항목을 다시 정리하면 다음과 같다.

```bash
bin/setup                    # 처음 한 번 (gem, DB)
bin/dev                      # Rails + Tailwind watch + 로컬 Traccar 컨테이너
bin/rails demo:seed          # 데모 데이터 (compose와 달리 자동 실행되지 않는다)
bin/rails "demo:drive[1번]"  # 시뮬레이터 (docker compose exec 없이 바로)
```

`bin/dev`는 Docker가 있으면 Procfile.dev의 `traccar`(`bin/traccar dev`)로 컨테이너 `where-is-my-bus-traccar`를 띄우고, Rails에 `TRACCAR_API_BASE_URL`(`http://localhost:8082`)·토큰 환경변수를 채우고 `0.0.0.0`에 바인딩한다(컨테이너가 호스트 Rails로 이벤트를 포워딩하려면 필요하다. 같은 네트워크에서 개발 서버가 보이는 점에 주의). Traccar를 쓰지 않으려면 `TRACCAR=0 bin/dev`.

| 항목 | `docker compose` | `bin/dev` |
|---|---|---|
| Rails | 컨테이너 | 내 PC (Ruby 환경 필요) |
| Rails → Traccar | `http://traccar:8082` | `http://localhost:8082` |
| Traccar → Rails 이벤트 | `http://rails:3000` | `http://host.docker.internal:<Rails 포트>` |
| 데모 시드 | 첫 기동 때 자동 | 직접 `demo:seed` |
| Traccar 데이터 | 이름 있는 볼륨 | `tmp/docker/volumes/traccar` |
| 초기화 | `docker compose down -v` | `bin/traccar reset` 뒤 `bin/rails traccar:sync` |

Traccar만 따로 다루는 명령은 `bin/traccar [up|down|status|logs|reset]`이다. `reset`은 Traccar 데이터를 지우고 Rails의 `traccar_*_id`를 비운 뒤 새로 기동한다. 그 뒤 `bin/rails traccar:sync`로 노선·정류장·차량을 Traccar에 다시 등록한다(운영에서는 실행되지 않는다).

> 이 방식의 컨테이너 기동·종료와 `demo:drive` 이벤트 도착은 실제 Docker에서 끝까지 확인하지 않았다. 막히면 `bin/traccar status`와 `bin/traccar logs`부터 본다.

## 초기화

```bash
docker compose down -v        # 컨테이너와 데이터(Rails DB, Traccar DB)를 모두 지운다
docker compose down           # 컨테이너만 지우고 데이터는 남긴다
```

Rails DB와 Traccar DB는 **함께** 초기화해야 한다. 한쪽만 지우면 ID가 어긋난다 (`docs/future-improvements.md` 19번).

`docker compose up`을 한 번이라도 실행했으면 컨테이너 2개(`where-is-my-bus-rails-1`, `where-is-my-bus-traccar-1`), 네트워크 `where-is-my-bus_default`, 볼륨 4개(`where-is-my-bus_rails-storage`, `_rails-tmp`, `_traccar-data`, `_traccar-logs`)가 남는다. `bin/dev`로 갈아탈 때 꼭 지울 필요는 없지만 쓰지 않을 거라면 `docker compose down -v`로 정리한다. 이미지(`traccar/traccar:6`, `Dockerfile.dev` 빌드 결과)는 남으며 `docker image rm`으로 따로 지운다. `bin/traccar`의 컨테이너와 `tmp/docker/volumes/traccar`는 별개라 영향이 없다.

## 실제 폰으로 시험하기

`driver_app`이 등록 때 받는 위치 전송 주소(`TRACCAR_SERVER_URL`)는 기본이 `localhost`라 폰에서는 닿지 않는다.
같은 Wi-Fi의 PC 주소로 바꿔서 다시 띄운다.

```bash
TRACCAR_SERVER_URL=http://<PC의 LAN 주소>:5055 docker compose up -d
```

앱의 `adminUrl`에는 `http://<PC의 LAN 주소>:3000`을 입력한다.

운전자 앱 자체를 로컬에서 시험하는 방법은 아래 "운전자 앱 로컬 시험"을 본다.

## 운전자 앱 로컬 시험

`driver_app/README.md`의 "iOS 시뮬레이터로 e2e 확인하기"가 시나리오·위치 좌표의 기준이다. 여기에는 환경 준비와 막혔던 지점만 적는다.

### 준비

1. **Flutter**: `driver_app/.tool-versions`에 `flutter 3.47.9-stable`(Dart 3.13)로 고정했다. `asdf plugin add flutter && asdf install` 후 `cd driver_app && flutter pub get`. Dart를 따로 설치하지 않는다(Flutter에 들어 있다. `brew install dart`는 서드파티 tap이라 신뢰 오류가 난다).
2. **`flutter doctor`**: iOS는 Xcode만 있으면 되고(이 앱은 CocoaPods 대신 SwiftPM으로 SDK를 받는다) Android 툴체인 경고는 iOS 시험에 무관하다. Android 에뮬레이터는 `localhost` 대신 `10.0.2.2`로 서버에 붙는다.
3. **서버**: `docker compose up -d --build` 또는 `bin/dev` + `bin/rails demo:seed`. 차량 PIN은 시드 출력이나 관리자 화면 차량 상세("PIN 재발급")에서 얻는다.
4. **시뮬레이터 기기**: `xcrun simctl list devices available`이 비어 있으면 런타임만 있고 기기가 없는 것이다. `xcrun simctl create`나 Xcode의 Devices and Simulators에서 만든다.

```bash
xcrun simctl boot <UDID> && open -a Simulator    # Flutter는 부팅된 기기만 인식한다
cd driver_app && flutter run -d <UDID>           # 화면은 Simulator 앱 창에 뜬다
```

앱 등록 화면에는 시뮬레이터에서 `http://localhost:3000`(compose의 `RAILS_PORT`를 바꿨으면 그 포트)과 PIN을 넣는다.

### 막혔던 지점

- **`bin/dev`가 `A server is already running`으로 종료**: 이미 떠 있는 Rails가 있다. `tmp/pids/server.pid`의 pid와 `lsof -nP -iTCP:3000 -sTCP:LISTEN`으로 확인하고 그 서버를 끈 뒤 다시 실행한다. foreman은 한 프로세스가 끝나면 나머지(css, traccar)도 내린다.
- **`no such table: route_stops`**: 개발 DB가 준비되기 전에 요청이 들어온 경우가 있다. `bin/rails db:migrate:status`로 마이그레이션이 모두 `up`인지 보고 새로고침한다. 계속되면 `bin/rails db:prepare`.
- **`traccar:sync`가 "정류장 연결 … /api/permissions → 400"으로 실패**: Rails에 저장된 `traccar_*_id`가 지금 Traccar에 없는 자원을 가리킬 때 난다(Traccar 데이터를 `bin/traccar reset` 없이 지웠거나 다른 Traccar였을 때). 없는 ID로의 수정(PUT)은 성공처럼 보이고 연결만 400이 된다. `bin/rails traccar:reset_ids` 뒤에 `traccar:sync`를 다시 실행한다. 같은 ID로 `sync`를 여러 번 실행하는 것은 안전하다(로컬 Traccar에서 두 번 실행해 둘 다 8/8 확인).
- **`flutter run`이 `No Xcode build settings have been found`**: 앞쪽 로그가 `Process timed out`(`xcodebuild -showBuildSettings`, Resolve Package Graph)이면 SwiftPM이 TraccarClientSDK(GitHub 릴리스 zip)를 받다가 Flutter의 60초 제한을 넘긴 것이다. `cd driver_app && xcodebuild -resolvePackageDependencies -project ios/Runner.xcodeproj -scheme Runner`로 미리 받아 두면 이후 빠르다. 무선 연결 기기는 느리니 시뮬레이터나 USB를 쓴다.
- **`failed downloading ... TraccarClientSDK.xcframework.zip` / `already exists in file system`**: GitHub 릴리스 다운로드가 일시적으로 504를 돌려줄 때 난다(`curl -sIL <URL>`이 `200`이면 풀린 것). 잔여 캐시가 남으면 `~/Library/Caches/org.swift.swiftpm`을 지우고 `flutter clean` 뒤 다시 실행한다.
- **실기기에서 설치 단계 실패**: `ios/Runner.xcodeproj`에 `DEVELOPMENT_TEAM`이 비어 있다. Xcode의 Signing & Capabilities에서 본인 Team을 골라야 하고, 번들 ID 충돌 때문에 시험용으로 바꾼 값은 커밋하지 않는다. 실기기는 `localhost` 대신 PC의 LAN 주소를 쓰고, iOS는 `Info.plist`의 평문 HTTP 예외가 필요하다.
- **의존성 업그레이드**: `flutter pub outdated`에 `traccar_client_sdk` 1.1.x가 보이지만 실기기 검증은 1.0.11 기준이다. 올릴 때는 별도 브랜치에서 `flutter test`·`flutter analyze`·실기기 확인까지 한다.

## 문제 해결

- **주소가 이 앱이 아닌 다른 화면을 보여준다 (언어 전환 KO/EN이 보이는 옛 디자인 등)**: 호스트 3000번을 이 컨테이너 말고 다른 프로세스(예: PC에서 직접 띄운 `bin/rails server`)도 듣고 있을 수 있다. `localhost`가 그쪽으로 연결되면 컨테이너 코드가 아니라 그 서버의 화면이 나온다. `lsof -nP -iTCP:3000 -sTCP:LISTEN`으로 확인하고, 다른 서버를 끄거나 `RAILS_PORT`로 포트를 바꾼다.
- **승객 화면에 "위치 확인 중"에서 안 넘어간다**: Traccar가 이벤트를 못 보내는 경우다. `docker compose logs traccar`와 `docker compose logs rails`에서 `/integrations/traccar/events` 요청이 오는지 본다.
- **시뮬레이터를 중간에 끊었다**: 운행이 열린 채 남는다. 같은 명령을 다시 실행하면 먼저 종료하고 새로 시작한다. 직접 닫으려면 `curl -X POST localhost:3000/integrations/traccar/trips/end -d deviceId=<deviceId>`.
- **전송 간격을 1초보다 짧게 하지 않는다**: 위치 시각은 1초 단위로 항상 앞으로만 가야 한다. 더 자주 보내면 시각이 실제 시간보다 앞서가서, 곧바로 다시 실행했을 때 첫 정류장 구간의 위치를 Traccar가 과거로 보고 건너뛴다 (그 정류장 방문이 기록되지 않는다). 그래서 시뮬레이터는 1초 미만을 거부한다. 시연 시간을 줄이려면 정차 시간(`dwell`)을 줄인다. 예: `demo:drive[1번,1,2]`
- **시뮬레이터를 두 개 동시에 돌리지 않는다**: 같은 기기에 서로 다른 위치가 섞여 들어가 정류장 진입/이탈이 번갈아 기록된다. 백그라운드로 돌릴 때는 `docker compose exec -d`를 쓰고 끝날 때까지 기다린다.
- **CSS를 고쳤는데 반영이 안 된다**: 컨테이너 시작 때 한 번 빌드한다. `docker compose exec rails bin/rails tailwindcss:build` 후 새로고침한다.
- **테스트 실행**: 호스트에서 `bin/rails test` (Docker 불필요, Traccar 호출은 모두 스텁).
