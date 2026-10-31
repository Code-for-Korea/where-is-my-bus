# 비즈니스 로직 검토 (origin/main `b43993d` 기준)

- 방법: `docs/erd.md`의 스키마·모델 규칙과 컨트롤러·서비스 코드를 대조하는 정적 읽기.
- 한계: 이 검토 환경에서 Ruby를 실행하지 못해(시스템 Ruby 2.6, 프로젝트 번들러 불일치) **동작을 재현하지는 않았다.** 아래 "확정"은 코드만으로 결론이 나는 것, "확인 필요"는 실행/운영 데이터로 검증해야 하는 것이다.
- 지난 세션의 가설 6개 중 5개가 코드로 확인됐고, 신규 3개를 찾았다.

## 요약

| # | 심각도 | 항목 | 상태 |
|---|---|---|---|
| 1 | 높음 | `Trip.ended_at`을 쓰는 코드가 없어 운행이 끝나지 않음 | 확정 |
| 2 | 높음 | 이미 지나간 버스가 "도착"으로 표시되고 버스 선택에서도 이김 | 확정 |
| 3 | 높음 | Bus·Stop 삭제 시 Traccar는 지워지고 DB 삭제는 FK로 실패할 수 있음 | 확정(FK 동작은 실행 미검증) |
| 4 | 중간 | `Bus.status`가 `register` 외에서는 무시됨 | 확정 |
| 5 | 중간 | 좋아요: 중복 방지·집계·응답이 서로 어긋남 | 확정 |
| 6 | 중간 | Region·Area 삭제는 Traccar 정리를 건너뜀 | 확정 |
| 7 | 중간 | `Stop.sequence` 유일성 제약 없음 | 확정 |
| 8 | 낮음 | 활성 `Trip` 생성 경쟁 상태 | 확정(발생 빈도는 확인 필요) |
| 9 | 낮음 | 기타(좌표 nil, PIN 소모 시점, 첫 사용자 operator 경쟁 등) | 일부 확인 필요 |

## 1. 운행(Trip)이 끝나지 않는다 — 높음

- `ended_at`을 읽는 곳은 `RouteProgress#trip`, `Integrations::TraccarController#positions`, `StopsController#debug_bus`뿐이고, **값을 쓰는 곳은 `lib/demo/seed.rb`(`demo:seed`)의 생성 시점 외에 없다.** 운행 종료 API도 없다(`config/routes.rb`).
- 결과:
  - 버스당 `Trip`은 첫 GPS 수신 때 생성된 뒤 영구히 활성이다. `no_trip` 상태는 한 번도 GPS를 못 받은 버스에서만 나온다.
  - GPS 신선도 검사가 없다(`RouteProgress#latest_gps`는 `recorded_at` 최신 1건을 시각과 무관하게 사용). 운행이 끝나 차고지에 선 버스, 꺼진 단말의 마지막 위치가 계속 "현재 위치"로 ETA에 반영된다.
  - `gps_logs`가 무한히 쌓인다(보존·정리 정책 없음).
- 확인 필요: 의도가 "Traccar 쪽에서 끊기면 stale 처리"라면, 그 판정 로직이 앱에 없다는 점이 결함이다.

## 2. 지나간 버스가 "도착"으로 표시되고 선택에서 이긴다 — 높음

- `RouteProgress#eta_to`는 `bus_stop.sequence >= target_stop.sequence`이면 같은 분기로 처리한다. 버스가 목표 정류장을 **이미 지나간 경우**(`>`)도 포함된다. 이때 `prev_stop`과의 거리로 `progress`를 계산하는데, 지나간 버스는 `bus_dist > seg_len`이라 `progress`가 1.0으로 잘려 `{ eta_minutes: 0, stops_away: 0 }`이 나온다.
- `RouteBusSelector`는 `stops_away` 최소인 버스를 고르므로, 지나간 버스(0)가 다가오는 버스(1 이상)를 항상 이긴다. 한 노선에 버스가 2대 이상이면 승객은 "곧 도착"을 보지만 실제로는 지나간 버스다.
- 순환 노선이 아니라는 전제에서도 발생한다. 순환·왕복 노선이면 더 심해진다(`nearest_stop`이 전역 최근접 정류장이라 방향 구분이 없음).

## 3. 삭제 순서 때문에 Traccar와 DB가 어긋난다 — 높음

- `Admin::BusesController#destroy`와 `Admin::StopsController#destroy`는 먼저 Traccar를 삭제하고, 성공하면 `destroy`를 호출한다. 정합성 정책 주석은 "Traccar 삭제 성공 시에만 DB 삭제"이다.
- 그런데 `Bus`·`Stop`에는 `has_many :stop_likes`가 없고 DB에는 `stop_likes → buses/stops` FK가 있다(`db/schema.rb`). 좋아요가 하나라도 있으면 `destroy`가 FK 위반으로 예외를 던질 수 있다(Rails의 SQLite 어댑터는 기본적으로 FK를 강제하므로 실제로 터질 가능성이 높다. 실행으로는 미검증).
- 이 경우 Traccar device/geofence는 이미 지워졌고 DB 레코드는 남는다. 이후 `sync_device`/`sync_geofence` 재동기화가 필요한 상태가 되고, 사용자에게는 500 오류가 보인다.
- 추가: `stop_likes.bus_id`가 "노선의 첫 번째 버스"(`route.buses.first`, `license_plate` 정렬)로 기록되므로, 좋아요가 한 번이라도 눌린 정류장의 노선에서 그 버스를 삭제할 수 없게 된다. 승객 좋아요가 운영자의 버스 삭제를 막는 구조다.

## 4. `Bus.status`가 대부분의 경로에서 무시된다 — 중간

- `status`를 거르는 곳은 `register`의 `Bus.active`뿐이다. `positions`(GPS 수신), `RouteBusSelector`, `StopsController#show/like`의 `route.buses.first`, `Integrations::TraccarController#routes`는 `inactive`/`deleted` 버스도 그대로 쓴다.
- `deleted` 값은 실제 `destroy`와 별개로 존재하고 폼에서 선택할 수 있다. "삭제됨"으로 바꿔도 승객 화면에는 계속 노출된다.
- 확인 필요: `inactive`·`deleted`의 의도된 의미. 소프트 삭제를 의도한 것이라면 `default_scope`나 연관관계에서 걸러야 한다.

## 5. 좋아요 로직 — 중간

- `routes.likes_count`: 어디서도 갱신하지 않는다(`counter_cache` 선언 없음, 증가 코드 없음). 그런데 `admin/routes/index`, `show` 화면이 이 값을 표시하므로 **항상 0**이다. 승객 화면은 `StopLike.count`를 직접 세므로 값이 서로 다르다.
- 중복 방지: "같은 세션이 1시간 내 1회"를 `exists?` 후 `create!`로 처리한다. `stop_likes` 인덱스는 모두 비유니크라 `ActiveRecord::RecordNotUnique` rescue는 **발생할 수 없는 죽은 코드**이고, 동시 요청은 중복 행을 만든다. 시간창(1시간) 규칙은 유니크 인덱스로 표현할 수 없어, 필요하면 트랜잭션·락 또는 시간 버킷 컬럼이 필요하다.
- 응답: 이미 좋아요를 눌렀든 새로 눌렀든 `already_liked: true`를 돌려준다. 클라이언트가 "방금 처리됨"과 "원래 눌렀음"을 구분할 수 없다.
- 의미: 좋아요 수는 `StopLike.where(stop_id:).count` 전체 행이므로, 한 세션이 1시간마다 한 번씩 계속 더할 수 있다. 의도라면 문제없지만 "정류장 좋아요 수"로 읽히는 UI와는 어긋날 수 있다.
- 코드 주석(`NOTE`)에 쿠키 삭제로 우회 가능하다는 점이 이미 명시돼 있어 결함으로 세지 않는다.

## 6. Region·Area 삭제는 Traccar 정리를 건너뛴다 — 중간

- `Route`·`Stop`·`Bus` 삭제는 Traccar 쪽을 먼저 지우지만, `Admin::RegionsController#destroy`와 `Admin::AreasController#destroy`는 곧바로 `destroy`만 호출한다. 모델의 `dependent: :destroy` 체인(Region→Area→Route·Bus→…)으로 하위 레코드가 모두 지워져도 Traccar device·group·geofence는 남는다(고아 리소스).
- 하위에 `StopLike`가 있으면 3번과 같은 FK 실패가 트랜잭션 중간에 발생할 수 있다(`destroy`는 트랜잭션으로 묶이므로 DB 쪽은 롤백됨).

## 7. 정류장 순서(`sequence`)에 유일성이 없다 — 중간

- 스키마는 `index(route_id, sequence)`가 비유니크, 모델 검증은 `presence`·정수·`> 0`뿐이다. 같은 노선에 같은 `sequence`가 둘 이상 들어갈 수 있다.
- `RouteProgress`는 `find { sequence == target.sequence - 1 }`, `bus_stop.sequence + 1`로 이웃 정류장을 찾으므로 중복·결번이 있으면 이전 구간 계산이 어긋나거나 ETA가 `progress = 1.0`(즉시 도착)으로 빠진다.
- DB 기본값은 0인데 모델은 `> 0`을 요구한다. 어긋난 이중 기준이다.

## 8. 활성 Trip 생성 경쟁 상태 — 낮음

- `positions`는 `where(ended_at: nil).first` 후 없으면 `create!`한다. 활성 Trip 유일성 제약이 없어서, 같은 버스의 첫 위치가 동시에 두 번 들어오면 활성 Trip이 둘 생긴다. 읽는 쪽은 `started_at` 내림차순 첫 건을 쓰므로 표시는 한쪽만 보이지만, GPS가 두 Trip에 나뉘어 쌓인다.
- 1번(Trip이 끝나지 않음)과 결합하면 활성 Trip은 첫 생성 이후 거의 바뀌지 않으므로 실제 발생 빈도는 낮다.

## 9. 기타 — 낮음 / 확인 필요

- `Stop.lat/lng`가 nil이면 `to_f`가 0.0이 되어 (0, 0) 좌표로 거리 계산에 들어간다(모델은 필수지만 DB는 nullable이라 모델 검증을 우회한 경로에서 가능).
- `register`는 응답 전에 PIN을 소모 처리한다. 응답이 단말에 닿기 전에 네트워크가 끊기면 PIN이 소모된 채 단말은 등록하지 못하고, 운영자가 PIN을 재발급해야 한다. 보안 측면의 의도된 트레이드오프로 보이나 운영 부담은 있다.
- `register` 속도 제한은 `Rails.cache.increment`로 시도 횟수를 센다. 캐시 스토어가 존재하지 않는 키의 `increment`를 어떻게 처리하는지(키 생성 여부)에 따라 잠금이 동작하지 않을 수 있다. 개발(`memory_store`)·운영(`solid_cache_store`) 양쪽에서 실제로 잠기는지 확인이 필요하다. 테스트 환경은 `null_store`라 이 경로가 테스트로 보호되지 않는다.
- `User`의 "첫 가입자는 operator"는 `User.count.zero?` 검사 후 생성이라 동시 가입 시 operator가 둘 이상 생길 수 있다.
- `PinCode` 모델·테이블은 인증에 쓰이지 않는다(레거시). 시드에만 남아 있다.
- `StopsController#show/detail/like`가 URL의 `region_slug`를 검증하지 않는다. 임의의 slug로도 정류장 페이지가 열린다.

## 권장 순서

1. 1번(Trip 종료/신선도)과 2번(지나간 버스 처리): 승객이 보는 ETA의 정확도에 직접 영향.
2. 3번·6번(삭제 순서와 FK): 운영자 작업이 중간에 실패해 Traccar와 어긋나는 문제.
3. 4번·7번: 제약을 DB에 추가할지, 모델에서만 막을지 정책 결정이 먼저 필요.
4. 5번은 `likes_count` 폐기 또는 갱신 중 하나를 정하는 것부터.
