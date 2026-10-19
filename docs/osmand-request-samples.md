# OsmAnd 요청 샘플 명세 — driver_app (Traccar Client SDK)

- 작성일: 2026-10-18
- 목적: P0 Todo 2 (GAP-2) — 운전자 앱이 실제로 송신하는 OsmAnd 프로토콜 요청의 파라미터·timestamp 단위·응답 기대값·인증 방식을 확정한다. Todo 5 (OsmAnd `/gps` 엔드포인트)의 구현 입력.
- 대상 SDK: `traccar_client_sdk` **1.0.11** (`driver_app/pubspec.lock` 고정 버전, pub.dev 2026-09-05 배포)

## 증거 등급 표기

| 등급 | 의미 |
|---|---|
| **[실측]** | 실제 Traccar 테스트 서버(`yehyunserver.iptime.org:5055`)에 보낸 프로브의 실제 HTTP 응답 (2026-10-18) |
| **[코드]** | driver_app이 사용하는 SDK v1.0.11 소스 코드 (traccar/traccar-client-sdk 저장소, 태그 v1.0.11) |
| **[서버소스]** | Traccar 서버 소스 (`traccar/traccar` master) 및 서버 자체 테스트 스위트에 담긴 실제 클라이언트 요청 샘플 |

가상 샘플 없음. 아래 모든 샘플은 위 세 출처 중 하나에 근거가 있으며, 값이 예시인 경우(코드에서 재구성한 요청) 명시했다.

---

## 0. 요약 (한눈에 보기)

| 항목 | 값 | 근거 |
|---|---|---|
| 전송 방식 | **POST**, `application/x-www-form-urlencoded`, 경로 `/` | [코드] HttpUploader.kt + Ktor formBuilders.kt |
| GET 사용 여부 | **SDK는 GET을 쓰지 않는다** (서버는 GET도 파싱함 — 프로토콜 호환) | [코드] + [서버소스] |
| 파라미터 | `id`(필수), `lat`, `lon`, `timestamp`(필수), `accuracy`, `altitude`, `speed`, `bearing`, `batt`, `charge`, `alarm` (옵션들은 값 있을 때만 전송) | [코드] |
| **timestamp 단위** | **초 (epoch seconds)** — 클라이언트가 `(epoch ms) / 1000`으로 변환해 전송 | [코드] |
| speed 단위 | **knots** (m/s × 1.94384, 소수 2자리 반올림) | [코드] |
| battery | `batt` = 0–100 정수(퍼센트), `charge` = true/false | [코드] |
| 인증 (앱→Traccar) | **없음** — `id`(= `traccar_unique_id`) 식별만. 헤더·토큰·패스워드 전송 불가 | [코드] |
| 인증 (Traccar→Rails) | `X-Ingest-Token` 공유 토큰 헤더 | [코드: Rails 컨트롤러] |
| 응답 (등록 단말) | 200 OK, 빈 body | [서버소스] — 실측 200은 실기기 검증 필요 |
| 응답 (미등록 단말) | query/form: **400** 빈 body / JSON 분기: **404** 빈 body | **[실측]** + [서버소스] |
| 재전송 | `buffer=true` → 영속 큐 + 지수 백오프(5s→5min), **원본 timestamp 유지** → 도착 순서 역전 | [코드] |

---

## 1. 증거 출처

| 출처 | 등급 | 내용 |
|---|---|---|
| `core/src/commonMain/kotlin/org/traccar/client/HttpUploader.kt` (태그 v1.0.11, main과 동일 확인) | [코드] | 요청 생성 코드 전체 — 파라미터 이름·순서·단위·timestamp 변환 |
| `core/src/commonMain/kotlin/org/traccar/client/Position.kt` | [코드] | `time: Long` = epoch 밀리초, `battery: Int?` |
| `core/src/commonMain/kotlin/org/traccar/client/Config.kt` | [코드] | `buffer: Boolean = true` 기본값 |
| `core/src/commonMain/kotlin/org/traccar/client/TrackerEngine.kt` | [코드] | 큐·백오프·오프라인 대기 = 재전송 메커니즘 |
| `core/src/androidMain/kotlin/org/traccar/client/PlatformModule.kt` | [코드] | `HttpClient(Android)` — 커스텀 헤더 없는 기본 클라이언트 |
| `core/src/androidMain/kotlin/org/traccar/client/AndroidBatteryProcessor.kt` | [코드] | 배터리 0–100 (`BATTERY_PROPERTY_CAPACITY`) |
| Ktor `formBuilders.kt` (ktorio/ktor main) | [코드] | `submitForm` 기본 = POST + `x-www-form-urlencoded` |
| `src/main/java/org/traccar/protocol/OsmAndProtocolDecoder.java` (traccar master) | [서버소스] | 파라미터 파싱·timestamp 휴리스틱·응답 코드 |
| `src/test/java/org/traccar/protocol/OsmAndProtocolDecoderTest.java` (traccar master) | [서버소스] | 실제 클라이언트 형식의 GET/POST 샘플 다수 |
| 실측 프로브 (본 문서 §2.3, §5) | **[실측]** | 테스트 서버 :5055 응답 — 400/404 확인 |
| `driver_app/ISSUE.md` §보류 | [코드] | `buffer: true` 고정, interval/heartbeat 30초, `stopDetection: false` |
| `app/controllers/integrations/traccar_controller.rb` | [코드] | Rails 수신 계약 — `device.uniqueId`, `position.fixTime` 등 |

---

## 2. POST 샘플 — driver_app SDK가 실제로 보내는 형식

### 2.1 요청 생성 코드 (SDK v1.0.11) [코드]

`HttpUploader.kt` — 이 코드가 요청의 형식을 100% 결정한다:

```kotlin
override suspend fun upload(position: Position): Boolean = try {
    val response: HttpResponse = httpClient.submitForm(
        url = config.serverUrl,
        formParameters = Parameters.build {
            append("id", config.deviceId)
            position.latitude?.let { append("lat", it.toString()) }
            position.longitude?.let { append("lon", it.toString()) }
            append("timestamp", (position.time / 1000).toString())
            position.accuracy?.let { append("accuracy", it.toString()) }
            position.altitude?.let { append("altitude", it.toString()) }
            position.speed?.let { append("speed", it.toKnots().toString()) }
            position.bearing?.let { append("bearing", it.toString()) }
            position.battery?.let { append("batt", it.toString()) }
            position.charging?.let { append("charge", it.toString()) }
            position.alarm?.let { append("alarm", it) }
        },
    )
    Log.log("Upload response ${response.status.value}")
    response.status.isSuccess()
} ...

private fun Double.toKnots(): Double = round(this * 1.94384 * 100) / 100
```

Ktor `submitForm(url, formParameters)`는 `encodeInQuery` 기본값 `false` → **`method = HttpMethod.Post; setBody(FormDataContent(...))`** (ktorio/ktor `formBuilders.kt` 원문: "Otherwise, form parameters are sent in a POST request body"). 즉 `Content-Type: application/x-www-form-urlencoded` POST 본문이다.

### 2.2 재구성한 HTTP 요청 (형식은 [코드] 검증, 값은 예시)

`serverUrl`은 register API(`POST /integrations/traccar/register`) 응답의 `traccarServerUrl`이며, 현재 테스트 서버 기준값 사용:

```http
POST / HTTP/1.1
Host: yehyunserver.iptime.org:5055
Content-Type: application/x-www-form-urlencoded

id=goseong-1-demo&lat=35.2285&lon=128.8894&timestamp=1760760000&accuracy=5.0&altitude=12.0&speed=0.0&bearing=0.0&batt=87&charge=false
```

- `timestamp=1760760000`은 예시 (epoch **초**, 10자리). 실제로는 `Position.time`(epoch ms)을 1000으로 나눈 정수.
- `id`와 `timestamp`는 항상 전송. 나머지는 해당 값이 있을 때만 (`?.let`).
- `speed`는 knots로 변환된 값 (예: 5 m/s → `9.72`).
- `alarm`은 이상 상황 문자열로, 평시 위치 전송에는 없음.
- 헤더에 인증 정보 없음 (§6 참고).

### 2.3 실측 트랜잭션 [실측] — 2026-10-18, 테스트 서버 :5055

미등록 단말 id(`docs-osmand-probe`)로 보낸 실제 프로브:

```text
=== [1] GET query params (프로토콜 호환 형식) ===
GET /?id=docs-osmand-probe&lat=35.228500&lon=128.889400&timestamp=<now>&hdop=5.0&altitude=12.0&speed=0.0&bearing=0.0
→ HTTP/1.1 400 Bad Request / content-length: 0

=== [2] POST form-urlencoded (SDK 본문 형식) ===
POST /  Content-Type: application/x-www-form-urlencoded
body: id=docs-osmand-probe&lat=35.228500&lon=128.889400&timestamp=<now>&hdop=5.0&altitude=12.0&speed=0.0&bearing=0.0
→ HTTP/1.1 400 Bad Request / content-length: 0
```

400의 원인이 "형식 오류"가 아니라 "미등록 단말"임을 확인한 판별 프로브 — 서버의 JSON 분기는 미등록 단말에 다른 코드(404)를 반환한다:

```text
=== [3] POST application/json (동일 미등록 단말) ===
POST /  Content-Type: application/json
{"location":{"timestamp":"2026-10-18T...Z","coords":{"latitude":35.2285,"longitude":128.8894,...}},"device_id":"docs-osmand-probe"}
→ HTTP/1.1 404 Not Found / content-length: 0
```

서버 소스와 정확히 일치: query 분기 미등록 단말 → `sendResponse(BAD_REQUEST)`, JSON 분기 미등록 단말 → `sendResponse(NOT_FOUND)` [서버소스]. 즉 **400/404 = 단말 미등록 신호**이며, 요청 형식 자체는 파싱되고 있었다.

참고: 시드 데모 버스 `goseong-1-demo`도 400이었다 — 로컬 DB 확인 결과 `traccar_device_id`가 비어 있어(Traccar 미프로비저닝) 서버에 단말이 존재하지 않기 때문. 등록 단말의 200 실측은 §9로 이관.

---

## 3. GET 샘플 — 프로토콜 호환 (driver_app SDK는 미사용)

⚠️ **driver_app의 SDK(v1.0.11)는 GET을 보내지 않는다** — 유일한 업로더인 `HttpUploader`가 항상 POST form을 쓴다(§2.1). GET 샘플은 (a) 서버가 GET을 파싱한다는 사실과 (b) 클래식 OsmAnd 클라이언트 형식 호환성 확인을 위해 기록한다. `/gps` 엔드포인트(Todo 5)는 GET도 지원하는 것이 프로토콜 호환상 안전하다.

### 3.1 서버 테스트 스위트의 실제 GET 샘플 [서버소스]

Traccar 서버 자체 테스트(`OsmAndProtocolDecoderTest.java`)에 담긴 실제 클라이언트 형식들:

```text
# 초 단위 timestamp + 전체 파라미터
GET /?id=123456&timestamp=1377177267&lat=60.0&lon=30.0&speed=0.0&bearing=0.0&altitude=0&hdop=0.0

# ISO8601 timestamp (구 OsmAnd 앱 형식)
GET /?id=902064&lat=42.06288&lon=-88.23412&timestamp=2016-01-27T18%3A55%3A47Z&hdop=6.0&altitude=224.0&speed=0.0

# 밀리초 timestamp (13자리 — 서버 휴리스틱이 ms로 처리)
GET /?id=902064&lat=42.06288&lon=-88.23412&timestamp=1442068686579&hdop=6.0&altitude=224.0&speed=0.0

# batt(배터리 %) 포함
GET /?id=861001000719969&lat=41.666667&lon=-0.883333&altitude=350.059479&speed=0.000000&batt=87
```

### 3.2 서버의 GET 파싱 근거 [서버소스]

`OsmAndProtocolDecoder.decodeQuery`는 `QueryStringDecoder(request.uri())`로 URI 쿼리를 파싱하고, 쿼리가 비면 **POST 본문을 같은 query-string 문법으로 파싱**한다:

```java
QueryStringDecoder decoder = new QueryStringDecoder(request.uri());
Map<String, List<String>> params = decoder.parameters();
if (params.isEmpty()) {
    decoder = new QueryStringDecoder(request.content().toString(StandardCharsets.US_ASCII), false);
    params = decoder.parameters();
}
```

서버가 받는 파라미터 이름 전체: `id`/`deviceid`(동의어), `timestamp`, `lat`, `lon`, `location`(`"lat,lon"` 형식), `speed`, `bearing`/`heading`(동의어), `altitude`, `accuracy`, `hdop`, `batt`, `charge`, `valid`, `driverUniqueId`, `notificationToken`, `cell`, `wifi`, 그 외 임의 파라미터 → position attributes로 저장.

---

## 4. timestamp 단위 — **초** (실제 샘플로 확인)

### 4.1 클라이언트 측 [코드]

- `Position.time: Long` = epoch **밀리초** (`Position.kt`; `Clock.System.now().toEpochMilliseconds()`).
- `HttpUploader.kt`가 전송 시 나눗셈: `append("timestamp", (position.time / 1000).toString())` → **epoch 초 (정수, 10자리)**.

### 4.2 서버 측 [서버소스]

`OsmAndProtocolDecoder`의 timestamp 처리:

```java
case "timestamp" -> {
    try {
        long timestamp = Long.parseLong(value);
        if (timestamp < Integer.MAX_VALUE) {
            timestamp *= 1000;   // 초(10자리) → ms로 환산
        }
        position.setTime(new Date(timestamp));  // 13자리는 ms로 그대로 통과
    } catch (NumberFormatException error) {
        if (value.contains("T")) {
            position.setTime(DateUtil.parseDate(value));      // ISO8601
        } else {
            position.setTime(DateUtil.parse(DATE_FORMAT, value)); // "yyyy-MM-dd HH:mm:ss"
        }
    }
}
```

- **초(10자리, < 2147483647)** → ×1000하여 ms로 해석 — driver_app SDK가 보내는 형식.
- 밀리초(13자리) → 그대로 ms로 해석 (테스트 스위트 샘플 `1442068686579`로 확인).
- ISO8601(`T` 포함)·`yyyy-MM-dd HH:mm:ss` 문자열도 지원 (구 OsmAnd 앱 호환).
- timestamp 누락 시 서버 수신 시각 사용.

⚠️ 장기 리스크 각주: epoch 초가 2147483648(2038-01-19)을 넘으면 위 휴리스틱이 초를 ms로 오인한다. 그 전에 서버 측(Traccar 또는 자체 `/gps`) 업데이트 필요. 자체 `/gps` 구현 시 이 휴리스틱을 그대로 복사할지는 Todo 5의 판단 사항 — 최소한 **초 우선**으로 명시적 파싱 권장.

### 4.3 Rails 현황 [코드]

Traccar 포워딩 경로(`traccar_controller.rb:56`)는 `PositionIngestor`에 위임하며, 공통 파서(`position_ingestor.rb`의 `parse_timestamp`)는 ISO8601(`T` 포함)과 숫자 epoch 초·밀리초를 모두 해석한다.

자체 `/gps` 엔드포인트(`app/controllers/gps_controller.rb`)는 **ISO8601 timestamp만 지원**하며, 숫자 epoch timestamp(초·밀리초 모두)는 `501 Not Implemented`로 거부한다. 이 차단은 의도적이다. SDK가 보내는 epoch 초의 직접 연동은 후속 작업으로 남겨졌으며, 그때는 초 → Time 변환(`Time.at(value.to_i)`)을 명시적으로 구현해야 한다.

---

## 5. 응답 기대값

| 상황 | 응답 | 근거 |
|---|---|---|
| 등록된 단말 + 정상 파라미터 | **200 OK, 빈 body** | [서버소스] `sendResponse(OK)` — 실측 200은 §9 (실기기 검증 필요) |
| 미등록 단말 (query/form 경로) | **400 Bad Request, 빈 body** | **[실측]** + [서버소스] |
| 미등록 단말 (`application/json` 경로) | **404 Not Found, 빈 body** | **[실측]** + [서버소스] |
| 등록 단말 + lat/lon 누락 | 200 (마지막 위치 폴백 `getLastLocation`) | [서버소스] |
| 서버에 대기 중인 커맨드가 있을 때 | 200 + 커맨드 문자열 body | [서버소스] (평시엔 빈 body) |
| Rails `/gps` + ISO8601 timestamp | **200 OK, 빈 body** (미등록 단말·좌표 누락도 200-ack) | [코드] `app/controllers/gps_controller.rb` |
| Rails `/gps` + 숫자 epoch timestamp | **501 Not Implemented, 빈 body** — ISO8601만 지원(§4.3) | [코드] `app/controllers/gps_controller.rb` |

**SDK의 성공 판정** [코드]: `response.status.isSuccess()` — **2xx만 성공**. 4xx/5xx/네트워크 오류는 전부 실패로 보고 재시도한다(§7 백오프). 즉 서버가 4xx를 반환하면 SDK는 무한 재시도한다(백오프로 완화되지만 끝나지 않음). Rails의 "검증 실패도 200-ack" 계약(`traccar_controller.rb:62-63` 주석 — 포워딩 재시도 폭주 방지)과 같은 원리가 클라이언트 측에도 적용된다. 자체 `/gps`도 같은 원칙을 따른다: 토큰 인증이 없어 401 경로는 없고, 미등록 단말·좌표 누락은 200-ack으로 무시한다. 숫자 epoch timestamp만 예외적으로 501로 거부한다(§4.3) — SDK가 이 응답을 받으면 백오프 재시도를 반복하므로, SDK 직접 연동 시에는 epoch 지원 추가가 선행돼야 한다.

---

## 6. 인증 방식

### 6.1 앱 → Traccar (:5055): 인증 없음 [코드]

- 요청에 토큰·패스워드·서명 없음. 단말 식별은 `id` 파라미터(= `traccar_unique_id`)뿐이다.
- `PlatformModule.kt`: `single { HttpClient(Android) }` — **커스텀 헤더를 추가하지 않는 기본 클라이언트**. `HttpUploader.kt`도 `submitForm`에 헤더를 붙이지 않는다. 즉 **운전자 앱 SDK는 어떤 커스텀 헤더(`X-Ingest-Token` 포함)도 보낼 수 없다.**
- 클래식 OsmAnd 프로토콜의 `key`(패스워드) 파라미터도 SDK는 전송하지 않고, 서버 디코더에도 패스워드 검사가 없다.

⚠️ **Todo 5 설계 입력**: 앱의 전송 대상을 바꾸는 유일한 수단은 register API 응답의 `traccarServerUrl` 값이다(경로 포함 가능, 예: `http://host:port/gps`). 따라서 `/gps`가 `X-Ingest-Token` 헤더를 요구하면 **운전자 앱의 직접 전송은 불가능**하다(헤더를 붙일 수 없어서). 헤더 토큰은 Traccar→Rails 포워딩 경로에만 성립한다. 실행 계획 L197("X-Ingest-Token 인증은 유지")과 이 사실의 정합성은 Todo 5에서 결정할 사항이며, 이 문서는 사실만 기록한다.

### 6.2 Traccar → Rails (`/integrations/traccar/positions`): `X-Ingest-Token` [코드]

- Traccar `forward.header` 설정으로 토큰 헤더 주입 (`docs/traccar-integration.md:61-64`: `forward.enable=true`, `forward.url`, `forward.json=true`, `forward.header`).
- Rails는 `X-Ingest-Token`을 timing-safe 비교로 검증, 실패 시 401. 토큰 미설정 시 fail-closed(전면 401) (`traccar_controller.rb:79-91`).
- per-device 인증(Device 스키마 + credential)은 P1 (P0 가드레일).

---

## 7. 지연 전송 / 재전송 사례

### 7.1 메커니즘 [코드]

driver_app은 `buffer: true` 고정(`ISSUE.md` §보류 — "전송 실패 재시도 큐"). SDK v1.0.11 `TrackerEngine.kt`:

```kotlin
if (buffer) {
    queue.enqueue(final)          // 영속 큐(sqldelight tracker.db)에 적재
    pipelineWakeUp.trySend(Unit)
} else {
    uploader.upload(final)
}
```

```kotlin
private suspend fun syncLoop() {
    var backoff = initialBackoff          // 5.seconds
    while (currentCoroutineContext().isActive) {
        val pending = queue.peek()
        when {
            pending == null -> pipelineWakeUp.receive()
            !network.isOnline.value -> {
                Log.log("Offline, waiting for network")
                network.isOnline.first { it }          // 오프라인 → 네트워크 복귀까지 대기
            }
            uploader.upload(pending) -> {
                queue.removeFirst()                     // 성공 → 큐에서 제거
                backoff = initialBackoff
            }
            else -> {
                Log.log("Upload failed, retrying in $backoff")
                delay(backoff)
                backoff = (backoff * 2).coerceAtMost(maxBackoff)   // 5s → 10s → ... → 5min
            }
        }
    }
}
```

- 오프라인 구간의 위치는 **영속 DB 큐**에 쌓이고, 네트워크 복귀 후 하나씩 순서대로 업로드된다.
- 업로드 실패(서버 4xx/5xx/타임아웃 포함) 시 지수 백오프(5초 시작, 최대 5분)로 재시도한다.

### 7.2 와이어 형태 (재전송 요청의 특징)

재전송 요청은 §2의 POST와 **형식이 동일**하되, `timestamp`가 **수신 시각이 아니라 원본 fix 시각(초)**이라는 점이 다르다:

```text
# 예: 10:00:00에 측정된 위치가 10:07:30에(네트워크 복귀 후) 도착
POST / HTTP/1.1
Content-Type: application/x-www-form-urlencoded

id=<traccar_unique_id>&lat=35.2285&lon=128.8894&timestamp=1760758800&...   # ← 10:00:00 (원본, 7.5분 전)
```

- 큐는 FIFO(`peek`/`removeFirst`)이므로 재전송은 원래 순서대로 나가지만, 실시간 위치와 섞여 도착하면 **수신 순서와 timestamp 순서가 역전**된다(늦게 도착한 오래된 위치).
- 이것이 실행 계획 §0.5의 "CurrentPosition은 recorded_at 역전 재전송이 최신 위치를 덮어쓰지 않는다" 설계가 필요한 근본 원인이다. Todo 5의 `/gps`도 동일하게 대응해야 한다.

### 7.3 실측 시도와 한계

- 미등록 단말로 백dated(600초 전) timestamp POST 프로브 → 400 [실측]. 400의 원인은 단말 미등록이지 시각이 아니다(§2.3 판별).
- 서버 디코더 소스에는 timestamp 신선도(staleness) 검사가 없다 [서버소스] — 오래된 위치도 수용하는 구조.
- **등록된 실기기 단말의 백dated 수용 + 실제 재전송 요청 캡처는 실기기 검증 필요** (§9).

---

## 8. 파라미터 → Traccar/Rails 매핑 (Todo 5 입력)

| OsmAnd 파라미터 | SDK가 보내는 값 | Traccar 내부 저장 | 포워딩 JSON 경로 | 단위/비고 |
|---|---|---|---|---|
| `id` | `config.deviceId` = `traccar_unique_id` | deviceId | `device.uniqueId` | Rails 컨트롤러가 실제로 읽는 필드 [코드] |
| `lat` / `lon` | 위도/경도 (`Double.toString`) | latitude / longitude | `position.latitude` / `position.longitude` | Rails가 읽음 [코드] |
| `timestamp` | epoch **초** | fixTime (Date) | `position.fixTime` (ISO8601 문자열) | Rails는 `fixTime \|\| deviceTime`을 ISO8601로 파싱 [코드] |
| `speed` | **knots** (m/s × 1.94384) | m/s (`convertSpeed(v, "kn")`) | `position.speed` | 서버 디코더가 knots로 파싱 [서버소스]. 포워딩 JSON의 speed 단위는 Traccar API 관례(knots) — 전체 페이로드 캡처로 확정 권장(§9) |
| `bearing` | 도 (Double) | course | `position.course` | `heading`도 동의어로 수용 |
| `accuracy` | 미터 (Double) | accuracy | `position.accuracy` | `hdop`은 별도 attributes |
| `altitude` | 미터 (Double) | altitude | `position.altitude` | |
| `batt` | 0–100 정수 | attributes.batteryLevel | `position.attributes.batteryLevel` | `AndroidBatteryProcessor`가 0–100만 허용 [코드] |
| `charge` | true/false | attributes.charge | `position.attributes.charge` | |
| `alarm` | 문자열 | attributes.alarm | `position.attributes.alarm` | 평시 전송엔 없음 |

- 포워딩 JSON에서 Rails 컨트롤러가 실제로 읽는 필드: `device.uniqueId`, `position.latitude`, `position.longitude`, `position.fixTime`, `position.deviceTime` (`traccar_controller.rb:56-71`) [코드]. `course`/`attributes` 등 나머지 필드명은 Traccar API 직렬화 관례 기반 — 전체 페이로드 캡처는 §9.
- 현재 Rails `GpsLog`는 lat/lng/recorded_at만 저장한다 — speed/bearing/battery/accuracy는 현재 경로에서 폐기되며, Todo 3의 CurrentPosition/PositionHistory가 이를 받아내는 대상이다.

---

## 9. 실기기 검증 필요 항목 (P1 이관)

본 머신에서 확보 불가했던 항목. 사유: 테스트 Traccar 서버에 등록된 단말 id를 알 수 없음(로컬 DB의 유일 버스 `goseong-1-demo`는 `traccar_device_id` 없음 = 미프로비저닝, 실측 프로브 400 확인). 서버 로그·tcpdump 접근 수단도 없음(원격 서버, SSH 권한 없음).

1. **등록 단말의 200 응답 실측** — 서버 소스상 200·빈 body로 확정돼 있으나, 실제 테스트 서버 버전에서의 응답은 미확인.
2. **등록 단말의 백dated(재전송) 위치 수용 실측** — 서버 소스상 staleness 검사 없음으로 확정, 실측 미흡.
3. **오프라인→복귀 재전송 요청의 와이어 캡처** — 형태는 코드로 확정(§7.2), 실측 캡처만 남음. 실기기에서 네트워크 차단→복귀 후 tcpdump/프록시.
4. **Traccar→Rails 포워딩 JSON 전체 페이로드 캡처** — `course`/`attributes`/speed 단위 등 필드명 확정. Rails 컨트롤러가 읽는 5개 필드 외는 관례 기반 기술.
5. **iOS 플랫폼 동일성** — 업로더는 commonMain 공유 코드라 Android와 동일 예상 [코드], 실기기 확인 권장.

위 항목은 P0 Todo 5(`/gps` 구현)를 막지 않는다 — Todo 5가 필요로 하는 요청 형식·timestamp 단위·응답 계약·인증 제약은 모두 [코드]+[서버소스]+[실측 400/404]로 확정됐다.
