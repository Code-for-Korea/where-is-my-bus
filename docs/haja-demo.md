# 하자센터 시연 데이터 (서울 영등포구)

시골·도서 지역이 아닌 **도시 안에서** 서비스를 보여 주기 위한 시연 시드다. 하자센터(서울특별시 영등포구, 37.5251401, 126.9032761) 주변 1.5km 안의 정류장 5개로 단방향 순환 노선을 만들고, 시뮬레이터로 버스 한 대를 운행시킨다. 기존 고성 데모(`docs/local-demo.md`)와 같은 구조(Rails ↔ Traccar Geofence 이벤트)를 쓰므로 이 문서는 그 문서의 시연 절차를 아는 사람 기준으로 **데이터가 다른 부분만** 적는다.

## 정류장 좌표의 출처

정류장 좌표는 **OpenStreetMap(OSM) 노드**에서 가져왔다. 서울 열린데이터광장의 버스정류소 OpenAPI는 발급 키가 있어야 전수 조회할 수 있어(샘플 키는 1~5행만 허용) 쓰지 않았다. 그래서 이 좌표는 **서울시 공식 데이터가 아니다.** 각 좌표는 아래 OSM 노드 주소로 누구나 다시 확인할 수 있다.

| 정류장 | 위도 | 경도 | OSM 노드 |
|---|---|---|---|
| 영동초교 | 37.5252508 | 126.9068323 | https://www.openstreetmap.org/node/12512226846 |
| 신화병원 | 37.5244724 | 126.9053251 | https://www.openstreetmap.org/node/12534076733 |
| 영등포시장 | 37.5215029 | 126.9049984 | https://www.openstreetmap.org/node/12534076765 |
| 영등포역 | 37.5168407 | 126.9074712 | https://www.openstreetmap.org/node/357951991 |
| 영등포구청 | 37.5253315 | 126.8964059 | https://www.openstreetmap.org/node/357894954 |

정류장 Geofence는 30m 정사각형이라 서로 겹치면 안 된다. 영등포역 주변은 정류장이 촘촘해서(같은 정류장의 상행·하행 노드가 13~46m 차이) **한 정류장당 노드 하나만** 골랐고, 인접 정류장 사이는 최소 159m다.

## 시드가 만드는 것

| 항목 | 값 |
|---|---|
| 노선 | 하자센터 시연 노선 (단방향 순환: 영동초교 → 신화병원 → 영등포시장 → 영등포역 → 영등포구청) |
| 차량 | 서울70사1001 (하자01) |
| 정류장 | 위 표의 5개, 영등포구 지역에 속함 |

정류장·노선·차량은 관리자 화면과 같은 등록 서비스(`StopRegistration` 등)를 거치므로 **Traccar에도 Geofence·그룹·기기가 함께 만들어진다.** 차량 PIN(6자리)과 `deviceId`(hex 12자)는 자동 생성되고 시드 마지막에 출력된다.

## 사전 준비: 영등포구 지역 적재

시드는 지역을 만들지 않는다. 이미 적재된 영등포구(지역 코드 `1156000000`)를 찾아 쓰고, 없으면 아래 메시지로 실패한다.

```
지역 코드 1156000000(서울특별시 영등포구)를 찾을 수 없습니다. 먼저 bin/rails "regions:import[CSV 경로]"로 지역을 적재하세요.
```

지역 CSV는 `script/regions/build_kr_regions.py`로 만든다(사용법은 `script/regions/README.md`). 데이터 파일은 커밋하지 않는다.

```bash
bin/rails "regions:import[/경로/kr_regions.csv]"
```

## 로컬에서 실행

Traccar가 떠 있어야 한다. `bin/dev`는 Traccar 컨테이너를 함께 띄우고 `TRACCAR_*` 환경변수를 채우므로 그대로 쓸 수 있다. `docker compose`로 띄웠다면 아래 명령의 `bin/rails`를 `docker compose exec rails bin/rails`로 바꿔 실행한다.

```bash
bin/dev                            # Rails + Tailwind watch + 로컬 Traccar 컨테이너
bin/rails demo:seed_haja_center    # 시연 데이터 (여러 번 실행해도 안전하다)
bin/rails "demo:drive[하자01]"     # 시뮬레이터 (번호판 "서울70사1001"로도 된다)
```

- 승객 화면 http://localhost:3000 에서 영동초교 등의 정류장을 고르고 "하자센터 시연 노선"을 연다.
- `demo:drive`는 Rails(localhost:3000)와 Traccar(localhost:5055)가 모두 떠 있어야 한다. 시뮬레이터는 기본 **약 45km/h**로 움직이고(`BusSimulator`의 `speed_kmh: 45`), 정류장마다 6초 정차한다. 시연 시간을 줄이려면 `demo:drive[하자01,1,2]`처럼 정차 시간을 줄인다.
- 시드 출력의 PIN과 `deviceId`는 운전자 앱 등록에 쓸 수 있다(로컬 시험 방법은 `docs/local-demo.md` "운전자 앱 로컬 시험").

## 서버에 적재

운영에는 시드가 없고, `demo:seed`는 운영에서 abort하지만 **`demo:seed_haja_center`는 운영에서도 실행할 수 있다.** 데이터를 넣는 작업이므로 백업을 먼저 한다.

```bash
# 1. 백업 (서버에서. 절차는 docs/deployment.md "데이터와 백업")
./backup-storage

# 2. 시연 데이터 적재 (배포 PC에서)
bin/kamal app exec --reuse "bin/rails demo:seed_haja_center"

# 3. 확인: 지역 없는 정류장이 0이어야 한다
bin/kamal app exec --reuse 'bin/rails runner "Stop.where(region_id: nil).count"'

# 4. 운행 시뮬레이션은 서버에서 하지 않는다. 운전자 앱으로 등록·운행하거나,
#    로컬에서 서버를 가리켜 돌리려면 DEMO_RAILS_URL과 TRACCAR_OSMAND_URL을 지정한다.
```

서버에도 영등포구 지역이 먼저 적재돼 있어야 한다. 지역 적재는 `docs/deployment.md` "지역(Region) 도입 배포"의 절차(CSV를 서버로 올려 컨테이너 안에서 `regions:import`)를 따른다.

## 고성 데모와의 차이

| | `demo:seed` (고성) | `demo:seed_haja_center` |
|---|---|---|
| 운영자 계정 | 만든다 (`operator@example.com`) | 만들지 않는다 |
| 지역 | 만들지 않는다 | 만들지 않고, **이미 적재된 영등포구를 찾아 쓴다** (없으면 실패) |
| 운영 실행 | abort | 실행할 수 있다 |
| 정류장·노선·차량 | 6개·2개·2대 | 5개·1개·1대 |

## 문제 해결

- **"Traccar 연결을 기다리는 중..."이 반복되다가 실패한다**: 등록 서비스는 Traccar 호출과 한 트랜잭션이라 Traccar가 내려가 있으면 Rails 변경도 취소된다. 시드는 약 30회(2초 간격) 재시도하다가 포기한다. Traccar를 띄운 뒤(`bin/traccar status`로 확인, `bin/dev`를 다시 띄우거나 `bin/traccar up`) **같은 명령을 다시 실행한다.** 시드는 여러 번 실행해도 안전하다(이미 있는 것은 건너뛴다).
- **`demo:drive`가 "버스를 찾을 수 없습니다"**: 시드를 먼저 실행하지 않았거나 다른 DB를 보고 있다. `bin/rails demo:seed_haja_center`를 실행한다.
- **승객 화면이 "위치 확인 중"에서 안 넘어간다**: `docs/local-demo.md` "문제 해결"과 같은 원인(Traccar → Rails 이벤트 포워딩)이다.
- **지역 오류로 시드가 실패한다**: 위 "사전 준비"의 `regions:import`를 먼저 한다.
