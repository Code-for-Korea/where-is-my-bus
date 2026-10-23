# 로컬 데모 실행

Rails 앱과 Traccar 서버를 Docker로 띄우고, 폰 없이 시뮬레이터로 버스 운행을 흉내낸다.
설계 배경은 `docs/design-event-driven-rewrite.md`, 제품 요구사항은 `docs/product_requirements.md`.

## 준비물

- Docker Desktop (Compose 포함)
- 포트 `3000`(Rails), `8082`(Traccar 웹·API), `5055`(Traccar 위치 수신)이 비어 있어야 한다

## 실행

```bash
docker compose up -d --build          # 첫 실행은 이미지 빌드와 시드 때문에 몇 분 걸린다
```

첫 기동 때 새 DB가 만들어지면서 **시드가 자동으로 실행된다.** 시드는 관리자 계정, 정류장 6개, 노선 2개, 차량 2대를 만들고
**Traccar에도 그룹·Geofence·기기를 함께 만든다**. Traccar가 아직 기동 중이면 잠시 기다렸다가 재시도한다.
차량의 PIN과 `deviceId`, 관리자 로그인 정보는 `docker compose logs rails`에 출력된다.
다시 보고 싶으면 `docker compose exec rails bin/rails db:seed`를 실행한다 (여러 번 실행해도 안전하다).

| 주소 | 내용 |
|---|---|
| http://localhost:3000 | 승객 화면 |
| http://localhost:3000/admin | 관리자 화면 (시드가 출력한 계정으로 로그인) |
| http://localhost:8082 | Traccar 웹 UI |

## 시연 순서

1. 승객 화면에서 **고성병원**을 고르고(1번·2번 노선이 함께 선다) **1번 노선**을 연다.
2. 다른 터미널에서 운행을 시뮬레이션한다.

   ```bash
   docker compose exec rails bin/rails "demo:drive[1번,1번 노선]"
   ```

   버스 `1번`이 `1번 노선`으로 운행을 시작하고 정류장을 차례로 지나간다 (약 100초).
   인자는 `demo:drive[버스(번호판 또는 번호),노선명,전송간격초,정차초]`이고 뒤의 둘은 생략할 수 있다.
3. 승객 화면이 5초마다 갱신되면서 "위치 확인 중 → 터미널 정차 → 출발 → … → 내 정류장에 정차 중 → 이미 지나갔어요"로 바뀐다.
4. 관리자 대시보드의 "운행 중인 버스"와 "최근 정류장 방문"에서 같은 흐름을 볼 수 있다.
5. `demo:drive[2번,2번 노선]`을 돌리면 2번 버스가 1번 노선의 시장 정류장 영역을 지나가지만 **시장 이벤트는 오지 않는다** (노선별 Traccar 그룹 설계).

## 데이터가 흐르는 길

```
시뮬레이터 ── 운행 시작 API ──▶ Rails ── 기기를 노선 그룹으로 이동 ──▶ Traccar
     │
     └─ 위치(OsmAnd, :5055) ──▶ Traccar ── Geofence 진입/이탈 이벤트 ──▶ Rails (방문 기록) ──▶ 승객 화면
```

## 초기화

```bash
docker compose down -v        # 컨테이너와 데이터(Rails DB, Traccar DB)를 모두 지운다
docker compose down           # 컨테이너만 지우고 데이터는 남긴다
```

Rails DB와 Traccar DB는 **함께** 초기화해야 한다. 한쪽만 지우면 ID가 어긋난다 (`docs/future-improvements.md` 19번).

## 실제 폰으로 시험하기

`driver_app`이 등록 때 받는 위치 전송 주소(`TRACCAR_SERVER_URL`)는 기본이 `localhost`라 폰에서는 닿지 않는다.
같은 Wi-Fi의 PC 주소로 바꿔서 다시 띄운다.

```bash
TRACCAR_SERVER_URL=http://<PC의 LAN 주소>:5055 docker compose up -d
```

앱의 `adminUrl`에는 `http://<PC의 LAN 주소>:3000`을 입력한다.

> **현재는 앱으로 운행을 시작할 수 없다.** `driver_app`이 새 운행 시작·종료 API를 아직 쓰지 않아서, 앱의 "운행 시작"은 서버에 운행을 만들지 않고 Geofence 이벤트도 기록되지 않는다.
> 앱 수정은 `docs/future-improvements.md` 21번이다. 그때까지는 `demo:drive` 시뮬레이터로 시연한다.

## 문제 해결

- **승객 화면에 "위치 확인 중"에서 안 넘어간다**: Traccar가 이벤트를 못 보내는 경우다. `docker compose logs traccar`와 `docker compose logs rails`에서 `/integrations/traccar/events` 요청이 오는지 본다.
- **시뮬레이터를 중간에 끊었다**: 운행이 열린 채 남는다. 같은 명령을 다시 실행하면 먼저 종료하고 새로 시작한다. 직접 닫으려면 `curl -X POST localhost:3000/integrations/traccar/trips/end -d deviceId=<deviceId>`.
- **시뮬레이터를 두 개 동시에 돌리지 않는다**: 같은 기기에 서로 다른 위치가 섞여 들어가 정류장 진입/이탈이 번갈아 기록된다. 백그라운드로 돌릴 때는 `docker compose exec -d`를 쓰고 끝날 때까지 기다린다.
- **CSS를 고쳤는데 반영이 안 된다**: 컨테이너 시작 때 한 번 빌드한다. `docker compose exec rails bin/rails tailwindcss:build` 후 새로고침한다.
- **테스트 실행**: 호스트에서 `bin/rails test` (Docker 불필요, Traccar 호출은 모두 스텁).
