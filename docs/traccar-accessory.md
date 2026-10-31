# Traccar를 Rails 서버에 함께 올리기 (Kamal accessory)

외부 Traccar(`testtraccar.codefor.kr`)를 쓰지 않고, Rails를 올리는 서버 한 대에 Traccar 컨테이너를 Kamal **accessory**로 함께 올린다. 같은 서버를 비용 때문에 껐다 켜는 전제다([aws-server-operations.md](aws-server-operations.md)).

> **구성은 `config/deploy.yml`에 반영했지만 서버에는 아직 배포하지 않았다.** "확인함"은 로컬 도커에서 실행해 본 것이고, "확인하지 못함"은 서버에서 처음 올릴 때 확인한다.

## 구성

```
운전자 앱 ──위치(OsmAnd, 5055)──▶ [서버] Traccar 컨테이너 ──Geofence 이벤트──▶ Rails 컨테이너
                                       ▲                                      │ (kamal 도커 네트워크, 서버 밖으로 안 나감)
                                       └── Rails가 Traccar API 호출 ◀─────────┘
승객 ──HTTPS(443)──▶ kamal-proxy ──▶ Rails
```

- Rails ↔ Traccar는 같은 도커 네트워크(`kamal`) 안에서만 오간다. 이 네트워크 이름은 Kamal 2.11 소스에서 확인했다(`DEFAULT_NETWORK = "kamal"`).
- 서버 밖으로 여는 포트는 80/443(Rails)과 **5055(위치 수신)** 뿐이다. Traccar 웹/API(8082)는 **열지 않는다.** Rails가 내부 주소로 부르고, 사람이 Traccar 웹을 봐야 하면 accessory의 `port`에 `"127.0.0.1:8082:8082"`를 추가하고(서버 자신에게만 열린다) `ssh -L 8082:localhost:8082`로 터널을 쓴다. 초안에는 넣지 않았다.
- 기존 외부 Traccar에서 문제였던 것(누구나 계정을 만드는 `registration`, 5055가 응답 없음)이 이 구성에서는 처음부터 우리 설정이다.

## 확인함 (로컬, `traccar/traccar:6.14.4`)

1. **환경변수만으로 설정된다.** `CONFIG_USE_ENVIRONMENT_VARIABLES=true`를 주면 `traccar.xml` 파일 없이 설정할 수 있다. 토큰을 파일에 쓰지 않아도 되고, 이미지·git에 비밀값이 남지 않는다.
2. **환경변수 이름은 camelCase를 `_`로 나눈다.**

   | traccar.xml 키 | 환경변수 |
   |---|---|
   | `web.serviceAccountToken` | `WEB_SERVICE_ACCOUNT_TOKEN` |
   | `web.registration` | `WEB_REGISTRATION` |
   | `event.forward.url` | `EVENT_FORWARD_URL` |

   **`WEB_SERVICEACCOUNTTOKEN`(나누지 않은 이름)은 조용히 무시된다.** 서버는 정상으로 뜨지만 서비스 토큰이 적용되지 않아 `Authorization: Bearer`가 모두 400이다. 이름을 틀리면 이렇게 보이므로 위 표의 이름을 그대로 쓴다.
3. `WEB_SERVICE_ACCOUNT_TOKEN`을 주면 그 토큰으로 `/api/devices?all=true`가 200, 다른 토큰은 400, 토큰 없음은 401이고, 그 토큰으로 그룹을 만들 수 있다(Rails가 하는 일과 같다).
4. `WEB_REGISTRATION=false`면 `/api/server`가 `"registration": false`다.
5. 컨테이너는 root(uid 0)로 돌고, DB는 `/opt/traccar/data/database.mv.db`(H2)에 생긴다. root라서 호스트 디렉터리에 `chown 1000:1000`이 필요 없다(Rails와 다르다).
6. Kamal 2.11이 accessory 설정과 `servers.web.options`의 `network-alias`를 받고, 풀린 값이 의도와 같다: 앱 `--network-alias rails-app`, accessory 컨테이너 이름 `where-is-my-bus-traccar`, `--stop-timeout 30`, 볼륨 `/var/lib/where-is-my-bus/traccar:/opt/traccar/data`. 앱·accessory·kamal-proxy 모두 `--restart unless-stopped`로 뜬다(소스 확인).
7. **이벤트 포워딩이 끝까지 동작한다.** `deploy.yml`과 같은 환경변수로 Traccar를 띄우고 `rails-app` 별칭의 간이 수신기를 80번에 둔 도커 네트워크에서, 기기와 지오펜스를 만들고 위치를 보내자 `geofenceEnter` 이벤트가 `POST /integrations/traccar/events`로 도착했다(`Host: rails-app`, `X-Ingest-Token: <설정한 값>`, JSON 본문). 지오펜스 진입 외에 `deviceMoving` 같은 이벤트도 함께 온다(Rails는 모르는 것을 200 `ignored`로 받는다).
8. `.kamal/secrets`가 토큰 두 개에서 Traccar용 값을 풀어낸다(`bin/kamal secrets print`): `WEB_SERVICE_ACCOUNT_TOKEN`은 `TRACCAR_API_TOKEN`과 같고 `EVENT_FORWARD_HEADER`는 공백이 든 `X-Ingest-Token: <값>`으로 풀린다.
9. Rails 쪽 호스트 검사(`config.hosts`)는 `production.rb`에 공개 도메인과 `rails-app`을 소스에 직접 적었다. 운영 모드로 부팅하는 하위 프로세스에서 실제 `ActionDispatch::HostAuthorization` 미들웨어에 태워 도메인과 `rails-app:80`은 통과, 모르는 호스트는 403, `/up`은 호스트와 무관하게 통과함을 테스트로 확인한다. `deploy.yml`의 `proxy.host`·`network-alias`·`EVENT_FORWARD_URL`의 호스트가 이 목록에 없으면 테스트가 실패하는 것도 일부러 어긋나게 만들어 확인했다(`test/lib/production_hosts_test.rb`).

## 확인하지 못함

- 서버에서의 `kamal setup`/`kamal accessory boot traccar` 실제 실행.
- **진짜 Rails 컨테이너가** 포워딩을 받는지. 위 7번의 수신기는 간이 프로그램이었다. Rails 쪽은 호스트 검사 단위 테스트까지만 확인했다. `assume_ssl`이라 평문 80으로 들어와도 HTTPS 리다이렉트가 없을 것으로 보지만 실제로는 보지 못했다. **첫 배포에서 가장 먼저 볼 것이다**(아래 "첫 배포 후 확인").
- kamal-proxy로 5055를 HTTPS로 감싸는 방법(아래 "위치 수신 암호화").
- 메모리: Rails + Traccar(Java) + kamal-proxy를 한 서버에 올렸을 때의 사용량. `docker stats`로 실측해서 인스턴스 크기를 정한다(2GB는 빠듯할 수 있다).
- H2 DB가 EC2 중지(정상 종료)에서 안전한지, 백업 방법(아래).

## 설정 (`config/deploy.yml`)

실제 값은 `config/deploy.yml`을 본다. 요점만 적는다.

| 항목 | 값 | 이유 |
|---|---|---|
| `service` | `where-is-my-bus` (이전 `web`) | accessory 컨테이너 이름이 `<service>-traccar`가 되고 Rails가 이 이름으로 부른다 |
| `servers.web.options.network-alias` | `rails-app` | 배포마다 앱 컨테이너 이름이 바뀌어 Traccar가 부를 고정 이름이 필요하다 |
| Rails `env.clear` | `TRACCAR_API_BASE_URL=http://where-is-my-bus-traccar:8082`, `TRACCAR_SERVER_URL=http://where-is-my-bus.codefor.kr:5055` | 내부 통신. 도메인이 바뀌면 `TRACCAR_SERVER_URL`도 같이 바꾼다 |
| Rails `env.secret` | `TRACCAR_API_TOKEN`, `TRACCAR_INGEST_TOKEN` | 환경변수가 credentials보다 우선하므로 `production.yml.enc`에는 `traccar.*`를 두지 않는다 |
| accessory 이미지 | `traccar/traccar:6.14.4` | 버전 고정(`latest`는 배포 때마다 바뀔 수 있다) |
| accessory `port` | `5055:5055` | 위치 수신만 게시. 8082는 게시하지 않는다 |
| accessory `env` | `CONFIG_USE_ENVIRONMENT_VARIABLES`, `WEB_REGISTRATION=false`, `EVENT_FORWARD_URL/TYPE`, 비밀 `WEB_SERVICE_ACCOUNT_TOKEN`, `EVENT_FORWARD_HEADER` | 위 확인함 1~4, 7번 |
| accessory `volumes` | `/var/lib/where-is-my-bus/traccar:/opt/traccar/data` | H2를 호스트에 둔다 |
| accessory `options` | `stop-timeout: 30` | 서버 종료·재배포 때 DB를 닫을 시간. 효과는 확인하지 못했다 |

- **토큰**: 배포 PC의 환경변수 `TRACCAR_API_TOKEN`, `TRACCAR_INGEST_TOKEN`에서 `.kamal/secrets`가 Rails와 Traccar 양쪽 값을 만든다([deployment.md](deployment.md) 5). `openssl rand -hex 32`로 새로 만들고 비밀번호 관리자에도 보관한다. 로컬 데모 토큰(`dev-traccar-*`)은 쓰지 않는다. 쓰면 부팅이 실패한다.
- **서버를 정하면 `SERVER_IP`를 두 곳**(`servers.web.hosts`, `accessories.traccar.host`)에서 바꾼다.
- **호스트 검사**: `config/environments/production.rb`의 `config.hosts = [ "where-is-my-bus.codefor.kr", "rails-app" ]`로 **소스에 직접** 적었다(환경변수 `APP_HOST`는 쓰지 않는다. 환경변수화는 후속 작업, `future-improvements.md` 30번). 같은 이름이 `deploy.yml`에도 있으므로(`proxy.host`, `network-alias`, `EVENT_FORWARD_URL`) 어긋나면 테스트가 실패한다. 허용 호스트가 늘어나도 이벤트 수신은 `X-Ingest-Token`으로 인증하므로 내부 이름을 허용한다고 인증이 약해지지는 않는다.
- 공개 도메인(`https://where-is-my-bus.codefor.kr/...`)으로 포워딩하는 안은 서버가 자기 공인 주소로 되돌아오는 경로에 의존하고 DNS가 틀리면 이벤트가 끊겨서 택하지 않았다.

## 첫 배포 후 확인

1. `bin/kamal accessory details traccar`와 `bin/kamal app details`로 두 컨테이너가 떠 있다.
2. `curl -s -o /dev/null -w '%{http_code}\n' https://where-is-my-bus.codefor.kr/up`이 200.
3. 서버에서 `docker exec where-is-my-bus-traccar sh -c 'wget -qO- http://localhost:8082/api/server'`로 Traccar가 응답하고 `"registration":false`다.
4. 서버에서 `docker logs where-is-my-bus-traccar | tail`에 포워딩 오류가 없고, Rails 로그(`bin/kamal logs`)에 `POST /integrations/traccar/events`가 `200`으로 찍힌다. 가장 먼저 볼 것: 403이면 호스트 검사(`production.rb`의 `config.hosts`와 `network-alias`의 불일치), 401이면 토큰 불일치다.
5. 정류장을 등록하면 Traccar에 지오펜스가 생긴다(Rails가 서비스 토큰으로 호출하는 경로).

## 도메인(Host) 검사 (검토 결과와 결정)

`config.hosts`는 허용한 이름이 아닌 `Host` 헤더를 403으로 막는다. **지워도 되는지** 검토했다. 검토 결론은 "지우는 것을 추천"이었다.

**결정(2026-10-31): 지우지 않고 유지하되, 환경변수(`APP_HOST`, `INTERNAL_HOSTS`) 없이 도메인과 `rails-app`을 `production.rb`에 직접 적는다.** `lib/app_hosts.rb`와 그 테스트는 지웠고, 환경변수를 쓰는 방식으로 되돌리는 것은 후속 작업이다(`future-improvements.md` 30번). 아래 "확인한 것", "지우면 사라지는 것", "잃는 것"은 **삭제를 택할 때의 근거**로 남겨 둔다.

### 확인한 것

1. **프록시가 이미 같은 일을 한다.** kamal-proxy는 등록한 호스트(`proxy.host`)가 아닌 요청을 404로 막는다. 로컬 실험에서 다른 이름, 내부 별칭 `rails-app`, IP 직접 접속이 모두 Rails에 닿기 전에 404였다. 인터넷에서 Rails로 가는 길은 이 프록시 하나뿐이다(Rails 컨테이너는 포트를 게시하지 않는다). 즉 공개 경로에서 `config.hosts`는 두 번째 검사다.
2. **Rails가 `Host`를 쓰는 곳은 적다.** `request.url`을 로그인 뒤 돌아갈 주소로 세션에 저장하는 곳(`authentication.rb`)과 로그인 폼의 절대 주소(`session_url`)가 있다. 이 값이 위조된 `Host`로 만들어지려면 프록시를 우회해야 한다. 비밀번호 재설정 메일은 `Host`가 아니라 `action_mailer.default_url_options`의 `example.com`을 쓴다(아래 "알게 된 문제").
3. **프록시를 우회할 수 있는 건 같은 서버의 `kamal` 네트워크 안 컨테이너뿐이다.** 지금은 Traccar와 kamal-proxy만 있다. 이 네트워크에 신뢰할 수 없는 컨테이너를 올리지 않는 한 위험이 없다.
4. Rails 운영 템플릿은 `config.hosts`를 주석 처리해 두고 쓰지 않는 것이 기본이다. 지운다는 것은 Rails의 기본 상태로 돌아간다는 뜻이다.

### 지우면 사라지는 것

- `production.rb`의 `config.hosts`와 `host_authorization`, `test/lib/production_hosts_test.rb`(`network-alias: rails-app`은 Traccar가 부르는 이름이라 **남긴다**)
- **Traccar 이벤트가 403으로 막힐 수 있는 실패 경로.** 이름이 어긋나면 Traccar가 재시도를 쏟아내고 도착 정보가 끊긴다.
- 도메인을 바꿀 때 고칠 곳이 하나 줄어든다: `proxy.host`, `TRACCAR_SERVER_URL`, 운영 credentials의 `site_url`만 남는다(`production.rb`의 도메인 없음).

### 잃는 것

- **프록시 설정이 틀렸을 때의 안전망.** 예를 들어 `proxy.host`를 비우면 와일드카드(`kamal-proxy deploy --host`의 도움말에 "empty for wildcard")라 어떤 이름으로도 Rails가 응답한다. 이때 `config.hosts`가 있으면 막아 준다. 대응: `proxy.host`를 비우지 않는다. `deploy.yml`에 필수라고 주석을 단다.
- 같은 서버에 나중에 다른 앱을 같은 프록시로 올리면 앱마다 호스트로 나뉘므로 영향이 없다.

### 채택한 방식: `config.hosts`를 소스에 직접 쓰기

```ruby
# config/environments/production.rb
config.hosts = [ "where-is-my-bus.codefor.kr", "rails-app" ]
config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
```

- 환경변수가 없으므로 이미지를 빌드할 때(`assets:precompile`)도 값이 있고 `if` 가드가 필요 없다(`nil.strip` 문제가 없다).
- **도메인이 두 파일에 적힌다**(`production.rb`, `deploy.yml`의 `proxy.host`). 도메인을 바꾸면 둘을 같이 바꿔야 하고, 한쪽을 빼먹으면 `proxy.host`는 통과하는데 Rails가 403을 줘서 **사이트 전체가 막힌다.** `test/lib/production_hosts_test.rb`가 `deploy.yml`의 `proxy.host`, `network-alias`, `EVENT_FORWARD_URL` 호스트가 허용 목록에 있는지 비교하므로 테스트를 돌리면 잡힌다. **이 저장소의 CI에는 테스트 잡이 없어서 로컬에서 돌려야 한다**(AGENTS.md).
- 환경변수 5가지 조합을 지원하던 이전 모듈에서 얻은 동작은 그대로다(공개 도메인과 내부 이름 허용, 그 밖은 403, `/up`은 예외).
- 후속 작업(환경변수화)은 `APP_HOST`를 `deploy.yml` 한 곳에서 내리고 `production.rb`가 읽는 방식이다. 이때 `if ENV["APP_HOST"].present?` 가드가 필요하다.

### 하지 않을 것

내부 통신(Traccar → Rails)을 HTTPS로 바꾸지 않는다. `http://rails-app:80`은 같은 서버의 도커 브리지 안에서만 오가고 서버 밖으로 나가지 않는다. 내부 HTTPS는 내부 이름용 인증서를 따로 관리해야 해서 얻는 것보다 비용이 크다. 그래도 요구한다면 공개 주소(`https://where-is-my-bus.codefor.kr/...`)로 포워딩하는 방법이 있지만 서버가 자기 공인 주소로 되돌아오는 경로에 의존하고 DNS가 틀리면 이벤트가 끊긴다.

### 알게 된 문제 (이번 검토와 별개)

`config.action_mailer.default_url_options`가 `{ host: "example.com" }`이고 SMTP 설정이 없다. 로그인 화면에 "비밀번호 찾기" 링크가 있어 **운영에서 비밀번호 재설정 메일이 나갈 수 없고, 나가더라도 링크가 `example.com`이다.** 메일을 쓸지 정해야 한다. 쓰지 않으면 "비밀번호 찾기"를 숨기는 것이 낫다.

## 위치 수신(5055)을 HTTPS로 (요구사항: HTTPS를 쓴다)

HTTPS를 쓰기로 했으므로 5055 평문 전송은 목표 구성이 아니다. 이전에는 "평문으로 시작"했지만 이 절이 그것을 대체한다. 아래 실험은 모두 로컬 도커에서 `basecamp/kamal-proxy:v0.9.2`(Kamal 2.11의 최소 버전)와 `traccar/traccar:6.14.4`로 했고, TLS 인증서 발급은 시험하지 못했다(공개 DNS가 필요하다).

### 확인한 것 (로컬)

1. kamal-proxy는 **등록한 호스트가 아닌 요청을 모두 404로 막는다**(다른 이름, 내부 별칭 `rails-app`, IP 직접 접속 모두).
2. **Traccar 5055는 기기 ID가 등록되지 않은 요청에는 어떤 경로든 400을 준다**(`/`, `/up`, 모르는 `id` 모두). 그래서 kamal-proxy의 기본 헬스체크(`/up`, 2xx 필요)로는 배포가 `target failed to become healthy`로 실패한다. `/`를 헬스체크 경로로 줘도 같다.
3. **등록된 기기의 위치 요청(`/?id=<등록된 ID>&lat=…&lon=…`)은 200**이다.
4. kamal-proxy는 헬스체크를 **다른 포트**로 돌릴 수 있다(`--health-check-port`). 웹 API(8082)의 `/api/server`로 헬스체크하고 5055로 트래픽을 보내는 배포가 성공했고, 프록시를 거친 위치 요청이 Traccar에 도달했다. **그러나 Kamal 2.11 설정에는 이 포트 항목이 없다**(`healthcheck`는 `path`, `interval`, `timeout`만, 소스 확인).
5. 웹 포트(8082)의 `/`는 200이지만 위치 수신이 아니라 웹 화면이다(요청 값을 무시). 위치 수신 대용으로 쓸 수 없다.
6. **같은 호스트에서 경로로 나누는 것이 된다.** kamal-proxy에 `--path-prefix=/osmand`(접두사 제거가 기본)로 Traccar를 등록하면 `/osmand/?id=…`는 Traccar로, `/`는 Rails로 간다. Kamal도 `path_prefix`, `strip_path_prefix`를 지원한다(소스 확인). 앞 절의 "경로로 나누기 어렵다"는 틀렸다.
7. Kamal이 "같은 호스트를 서로 다른 role이 SSL로 공유"하는 것은 막지만, 이 검사는 role만 대상이라 accessory는 해당하지 않는다(소스 확인). 인증서가 같은 호스트에 두 번 발급되는지는 확인하지 못했다.

### 결과: 두 가지 방법

| | A. 별도 이름 (`https://traccar.where-is-my-bus.codefor.kr`) | B. 같은 이름 + 경로 (`https://where-is-my-bus.codefor.kr/osmand/`) |
|---|---|---|
| 도메인 | 하나 더 | 늘지 않음 |
| 앱이 받는 주소 모양 | 지금과 같은 루트 주소(`https://호스트`) | 경로가 붙음. **앱의 `traccar_client_sdk`가 경로가 붙은 주소와 쿼리 문자열을 어떻게 만드는지 확인하지 못했다** |
| 인증서 | 이름마다 발급 | 같은 이름 하나(두 서비스가 한 이름에서 발급 문제 없는지 미확인) |
| Rails와 경로 충돌 | 없음 | `/osmand`를 Rails가 못 쓴다 |
| Traccar만 옮기기 | 레코드만 바꾸면 됨 | 프록시 설정까지 바꿔야 함 |

**추천: A.** 위 6번으로 B도 프록시 수준에서는 가능하지만, 앱 SDK가 경로가 붙은 주소를 올바르게 쓰는지 아직 모르고 A는 주소 모양이 지금과 같아 위험이 작다. 어느 쪽이든 5055는 서버 밖으로 열지 않으므로 보안 그룹에서 **5055를 닫고** `accessories.traccar.port`를 지운다(Rails와 kamal-proxy가 같은 도커 네트워크에서 전달한다).

### 얻는 것

- 위치와 `deviceId`가 평문으로 오가지 않는다(`future-improvements.md` 2번의 가장 큰 위험 해소).
- 앱의 **평문 허용(Android `network_security_config.xml`, iOS ATS 예외)을 모두 걷어낼 수 있다**(29번). 이전 절의 "평문 허용 범위를 좁힌다"는 이유도 필요 없어진다.
- 서버가 열어 두는 포트는 80, 443, 22뿐이다.

### 헬스체크 문제의 해법 (적용 전, 서버에서 확인 필요)

Traccar는 기본 헬스체크를 통과하지 못한다(위 2번). 방법이 둘이다.

1. **전용 기기 `healthcheck`를 만들어 쓴다 (Kamal 설정 안에서 해결).** Traccar에 기기(`uniqueId=healthcheck`)를 하나 만들고 accessory의 `proxy.healthcheck.path`를 `/?id=healthcheck&lat=0&lon=0`으로 준다. 위 3번대로 200이 된다. **함정: 기기를 만들려면 Traccar가 먼저 떠 있어야 하는데, `kamal accessory boot`는 컨테이너를 띄운 직후 프록시 배포를 해 헬스체크가 실패한다.** 그래서 2단계로 한다: ① 처음에는 `proxy` 없이 부팅하고 서비스 토큰으로 기기를 만든다, ② `proxy`를 추가하고 `bin/kamal accessory reboot traccar`. 배포 때만 헬스체크가 돌고 이 기기에 위치가 몇 건 기록될 수 있다(이벤트가 Rails로 포워딩되면 Rails는 모르는 기기를 200 `ignored`로 받는다). Kamal이 헬스체크 경로의 `?`를 그대로 넘기는지는 확인하지 못했다.
2. **kamal-proxy를 직접 호출한다.** `docker exec kamal-proxy kamal-proxy deploy …`에 `--health-check-port=8082 --health-check-path=/api/server`를 준다(4번에서 동작 확인). Kamal이 모르는 수동 단계라 재현성이 떨어지고, `kamal proxy reboot` 뒤에 유지되는지 확인하지 못했다.

**추천: 1.** Kamal 설정에 남기 때문이다.

### 아직 모르는 것

- Let's Encrypt가 두 이름(또는 한 이름 두 서비스)에서 발급되는지.
- 앱 SDK가 `https://` 주소로 위치를 보내는지(경로가 붙는 B는 더 불확실). **SDK 공식 문서는 HTTP 메서드, URL 형식, `serverUrl`에 경로를 붙일 수 있는지, 평문 지원 여부를 밝히지 않는다**(예시는 모두 `https://demo.traccar.org`뿐, 2026-10-31 확인; SDK 소스는 보지 못했다). 그래서 앱의 위치 전송 동작은 [traccar-integration.md](traccar-integration.md) "운전자 앱의 위치 전송"에 정리하고, 확정은 실제 앱 시험 뒤에 한다.
- 헬스체크 경로의 쿼리 문자열 처리, `kamal proxy reboot` 뒤의 경로 유지.
- 5055를 닫은 상태에서 Traccar가 컨테이너 네트워크로만 위치를 받는 동작(로컬에서는 같은 네트워크에서 전달됐지만 서버에서는 보지 못했다).
- 이미 등록된 휴대폰의 주소 갱신: 주소는 PIN 등록 때 휴대폰에 저장된다. **HTTPS 주소를 처음부터 쓰면 재등록이 필요 없다.** 이미 평문 주소로 등록된 폰이 생긴 뒤에 바꾸면 재등록이 필요하다.

## 위치 수신 주소: 도메인을 하나 더 두는가

**결론: 둔다.** 위치 수신용 이름을 승객 사이트와 분리한다. 제안: `traccar.where-is-my-bus.codefor.kr` (Cloudflare에서 **DNS 전용(프록시 끔)**, 값은 `where-is-my-bus.codefor.kr`을 가리키는 CNAME 또는 같은 IP의 A 레코드). 비용은 DNS 레코드 하나이고 HTTP에는 인증서가 필요 없다.

위치 수신이 HTTP(평문, 5055)인 한 아래 이유가 겹친다. 도메인 없이 `http://where-is-my-bus.codefor.kr:5055`로 써도 **동작은 한다.** 분리하는 이유는 동작이 아니라 보안과 나중에 바꾸는 비용이다.

### 이유

1. **평문 허용 범위를 위치 수신 이름 하나로 좁힌다 (가장 큰 이유).** 운전자 앱은 평문을 도메인 단위로만 허용한다. Android `network_security_config.xml`은 `<domain>` 단위, iOS `NSExceptionDomains`도 도메인 단위이며 **포트로 구분하지 못한다**(플랫폼 동작, 이 저장소의 두 파일이 도메인만 적는 것을 확인함). 위치 수신이 승객 사이트와 같은 이름이면 그 이름을 평문 허용에 넣어야 하고, 그러면 같은 이름의 **HTTPS 웹 서버 호출(PIN 등록, 운행 시작·종료)** 도 OS가 막아 주지 않는다. 앱 입력란에 `http://`로 잘못 적어도 통과한다(`adminUrl`은 운전자가 입력한다). 이름을 나누면 **승객 사이트는 계속 HTTPS만** 허용되고 평문은 위치 수신 이름에만 열린다. 이 저장소가 이미 겪은 상황이다: 지금 허용 목록은 테스트 서버 한 도메인이고 Traccar와 웹이 같은 이름이다([future-improvements.md](future-improvements.md) 29번).
2. **Cloudflare 프록시와 충돌하지 않는다.** 승객 사이트를 나중에 Cloudflare 프록시(주황 구름, DDoS 방어·캐시)로 돌리고 싶어도, 프록시는 허용된 일부 포트만 전달하고 5055는 그 목록에 없는 것으로 알고 있다(Cloudflare 문서로 확인하지 못함). 이름이 같으면 승객 사이트를 영원히 DNS 전용으로 둬야 한다. 분리하면 `traccar.…`만 DNS 전용으로 두고 사이트는 프록시를 켤 수 있다.
3. **HTTPS로 올릴 때 이름을 나누는 쪽이 위험이 작다.** kamal-proxy는 호스트 이름으로 요청을 나눈다. 같은 이름을 쓰려면 경로(`/osmand`)로 나눠야 하는데 프록시 수준에서는 되지만(로컬 실험) 앱 SDK가 경로가 붙은 주소를 어떻게 쓰는지 확인하지 못했다. 자세한 비교는 아래 "위치 수신(5055)을 HTTPS로"를 본다.
4. **Traccar만 다른 서버로 옮길 수 있다.** 이름이 Traccar 전용이면 그 레코드만 바꾸면 된다. 이름을 공유하면 Traccar를 옮길 때 이름도 새로 만들어야 한다.

### 이 저장소에서 확인한 것 — 주소는 휴대폰에 박힌다

- Rails의 PIN 등록 응답이 `traccarServerUrl`(= `TRACCAR_SERVER_URL`)을 앱에 돌려준다(`integrations/traccar_controller.rb`).
- 앱은 그 값을 `SharedPreferences`에 저장하고(`driver_registration.dart`) Traccar SDK 초기화에 그대로 쓴다(`tracking_controller.dart`). **다시 받아 오는 코드는 없다.**

그래서 **지금 정하는 이름과 주소가 등록된 모든 기사 휴대폰에 저장된다.** 나중에 바꾸면 기사마다 PIN을 새로 받아 다시 등록해야 한다(PIN은 1회용, 관리자 "PIN 재발급"). 도메인을 나눌지 지금 정하는 편이 싼 이유다. 같은 이유로 HTTP → HTTPS 전환도 주소가 바뀌므로(`http://…:5055` → `https://…`) 도메인 분리와 별개로 **재등록 문제가 남는다.**

→ 후속 개선 제안: 앱이 시작할 때 `GET /integrations/traccar/bus`처럼 이미 쓰는 호출에서 `traccarServerUrl`을 다시 받아 저장하게 하면 주소를 바꿔도 재등록이 필요 없다. 이 변경은 Rails 응답과 앱 코드를 함께 고쳐야 해서 이번 범위에 넣지 않았다. 구현하려면 `driver-app` 스킬의 절차(로컬 `flutter test`·`flutter analyze`)가 필요하다.

### 분리했을 때 바뀌는 곳 (아직 적용하지 않았다)

| 파일 | 바꿀 값 |
|---|---|
| `config/deploy.yml` `env.clear.TRACCAR_SERVER_URL` | `http://traccar.where-is-my-bus.codefor.kr:5055` |
| Cloudflare DNS | `traccar.where-is-my-bus.codefor.kr` 레코드(DNS 전용). Elastic IP를 쓰는 동안은 A 레코드, 나중에 IP가 바뀌는 방식(4장 B·C)으로 가면 **CNAME으로 두어 한 곳만 갱신**한다 |
| 앱 평문 허용 목록(Android `network_security_config.xml`, iOS `Info.plist`) | 이 이름 하나만 적는다. 현재 예전 테스트 서버 항목은 걷어낸다(29번) |
| Rails 호스트 검사(`production.rb`의 `config.hosts`) | **바꿀 것 없다.** 5055는 Rails가 받지 않는다 |
| Let's Encrypt | 필요 없다(HTTP). 나중에 kamal-proxy로 감쌀 때 이 이름으로 발급된다 |

### 분리하지 않아도 되는 경우와 단점

- **단점**: 관리할 이름이 하나 늘고 앱 허용 목록에 적을 값이 달라진다. 기사 앱 입력란에는 이 이름이 아니라 웹 서버 주소(`adminUrl`)를 적는다는 점을 안내해야 한다.
- 위치 수신을 곧바로 HTTPS로 올리고(다음 절의 kamal-proxy 방식) 평문 허용을 아예 쓰지 않는다면 1번 이유가 사라진다. 그래도 3번 때문에 별도 이름이 필요하다.

## 데이터와 백업

- Traccar 데이터(H2 파일)는 호스트 `/var/lib/where-is-my-bus/traccar`에 둔다. 컨테이너를 지워도 남는다.
- **실행 중인 H2 파일을 `cp`하면 깨질 수 있다.** SQLite와 같은 이유다. 안전한 방법은 Traccar를 잠깐 멈추고 복사하는 것이다.

```bash
docker stop <service>-traccar && tar -czf /var/backups/where-is-my-bus/traccar-$(date +%Y%m%d).tar.gz -C /var/lib/where-is-my-bus traccar; docker start <service>-traccar
```

  멈춰 있는 몇 초 동안의 위치는 못 받는다. 서버를 어차피 하루 한 번 껐다 켠다면 **끄기 직전에 백업**하는 편이 자연스럽다. 이 방법은 **확인하지 못함.**
- Traccar에 있는 것(기기, 그룹, 지오펜스)은 Rails DB의 `traccar_*` ID와 짝이다. **한쪽만 복원하면 어긋난다**(`future-improvements.md` 19번). Rails DB와 Traccar 데이터를 같은 시각에 백업한다.
- 운영에 H2는 권장되지 않는다고 이 저장소가 적고 있다(`compose.yaml` 주변 설정 주석, `future-improvements.md` 14번). 규모가 작아 지금은 H2로 시작하고, 문제가 생기면 그때 다른 DB를 검토한다.

## 껐다 켤 때의 위험

- **서버가 꺼져 있는 동안 운전자 앱은 위치를 보낼 수 없다.** 앱(Traccar Client SDK)은 `buffer`가 기본 켜짐이라(앱도 끄지 않았다) 보내지 못한 위치를 로컬 큐(SQLite, 앱을 껐다 켜도 남음)에 쌓고, 5초~5분의 지수 백오프로 재시도해 **서버가 켜지면 원래 시각 그대로 한꺼번에 보낸다**(SDK 공식 문서, `driver_app/ISSUE.md`). 이 쌓인 위치는 서버가 꺼지기 전 마지막 위치보다 새것이므로 Traccar가 **옛 시각의 Geofence 이벤트를 만들어 `stop_visits`에 오래된 방문이 기록될 수 있다.** 실제로 그렇게 기록되는지는 서버에서 껐다 켜 보며 확인하지 못했다. 운행 시간 밖에만 끄고, 운행이 끝난 상태(운전자가 "종료"를 누른 뒤)에서 끄면 앱이 위치를 보내지 않아 쌓이지 않는다.
- 같은 이유로 **켜 두는 시간은 운행 시간을 덮어야** 한다. 운행 중에 서버가 꺼지면 그 시간의 도착 정보는 비어 있다. 운행 시간표가 있는지 확인해야 한다.
- 켜진 직후 Traccar(Java)가 뜨는 데 수십 초가 걸린다(로컬에서 컨테이너를 띄우고 `/api/server`가 200이 되기까지 반복 확인했고, 정확한 초는 재지 않았다). 그동안의 위치는 못 받는다.

## 결정 대기

1. **위치 수신 HTTPS**: 요구사항으로 확정. 방법은 A(별도 이름 `traccar.where-is-my-bus.codefor.kr`, 추천)와 B(같은 이름 + `/osmand`). 헬스체크는 전용 기기 방식(추천). 적용하면 `deploy.yml`(`accessories.traccar.proxy`, `port` 삭제, `TRACCAR_SERVER_URL`을 `https://…`로), 보안 그룹의 5055 닫기, 앱의 평문 허용 제거가 따른다. **등록된 휴대폰이 생기기 전에 정한다.**
2. ~~도메인 검사 삭제~~ → **결정: 유지하되 소스에 직접 적는다**(적용됨). 환경변수화는 후속 작업.
3. 비밀번호 재설정 메일을 쓸지.
4. 서버 크기: **결정 `t4g.micro` + 스왑 2GB**([aws-server-operations.md](aws-server-operations.md) 6장).
5. 껐다 켜는 시간표(운행 시간). [aws-server-operations.md](aws-server-operations.md).
