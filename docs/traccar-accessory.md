# Traccar를 Rails 서버에 함께 올리기 (Kamal accessory)

외부 Traccar(`testtraccar.codefor.kr`)를 쓰지 않고, Rails를 올리는 서버 한 대에 Traccar 컨테이너를 Kamal **accessory**로 함께 올린다. 같은 서버를 비용 때문에 껐다 켜는 전제다([aws-server-operations.md](aws-server-operations.md)).

> **구성은 `config/deploy.yml`에 반영했지만 서버에는 아직 배포하지 않았다.** "확인함"은 로컬 도커에서 실행해 본 것이고, "확인하지 못함"은 서버에서 처음 올릴 때 확인한다.

> **현재 결정(2026-11-01): 동작을 먼저 확인하려고 첫 배포는 위치 수신을 평문 HTTP 5055(`http://where-is-my-bus.codefor.kr:5055`)로 한다. 이 문서의 HTTPS 설계(서브도메인 `traccar-where-is-my-bus.codefor.kr` + nginx)는 보류 중이고 반드시 후속으로 반영해야 한다.** 평문은 위치와 `deviceId`를 보호하지 못하므로 시험(소수의 기기, 실운행 전)에만 쓴다. 위험, 앱 허용 목록, 폰 재등록은 [deployment.md](deployment.md)의 "첫 배포의 위치 수신은 임시로 평문(HTTP)이다".

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
- 서버는 SSH 별칭 `web01.where-is-my-bus`로 두 곳(`servers.web.hosts`, `accessories.traccar.host`)에 적는다. IP는 `~/.ssh/config`에 있다.
- **호스트 검사**: `config/environments/production.rb`의 `config.hosts = [ "where-is-my-bus.codefor.kr", "rails-app" ]`로 **소스에 직접** 적었다(환경변수 `APP_HOST`는 쓰지 않는다. 환경변수화는 후속 작업, `future-improvements.md` 30번). 같은 이름이 `deploy.yml`에도 있으므로(`proxy.host`, `network-alias`, `EVENT_FORWARD_URL`) 어긋나면 테스트가 실패한다. 허용 호스트가 늘어나도 이벤트 수신은 `X-Ingest-Token`으로 인증하므로 내부 이름을 허용한다고 인증이 약해지지는 않는다.
- 공개 도메인(`https://where-is-my-bus.codefor.kr/...`)으로 포워딩하는 안은 서버가 자기 공인 주소로 되돌아오는 경로에 의존하고 DNS가 틀리면 이벤트가 끊겨서 택하지 않았다.

> **위치 수신 HTTPS를 적용하면 위 표의 accessory `port: 5055:5055` 행이 없어지고 `traccar-proxy`(nginx) accessory가 추가된다.** 지금 `deploy.yml`은 아직 평문 5055 구성이다. 설계와 검증 결과는 아래 "위치 수신(5055)을 HTTPS로".

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

Rails와 마찬가지로 Traccar도 HTTPS로 받아야 한다. **지금은 첫 배포의 동작 확인을 위해 이 설계를 보류하고 평문 5055로 먼저 배포한다(필수 후속 작업, 위 안내).** **이름과 방식 결정(2026-11-01): Rails는 `where-is-my-bus.codefor.kr`, Traccar는 `traccar-where-is-my-bus.codefor.kr`를 쓰고 두 이름을 같은 IP로 연결한다. 두 이름 모두 kamal-proxy가 443에서 받는다.** Traccar 자체는 계속 HTTP(5055)이고 TLS는 프록시가 끝낸다.

아래 실험은 모두 로컬 도커에서 `basecamp/kamal-proxy:v0.9.2`(Kamal 2.11의 최소 버전), `traccar/traccar:6.14.4`, `nginx:1.27-alpine`으로 했다. **자체 서명 인증서로 시험했고 Let's Encrypt 발급 자체는 시험하지 못했다**(공개 DNS와 서버가 필요하다).

### 확인한 것 (로컬)

1. **한 프록시가 두 이름을 동시에, 각자 다른 인증서로 받는다.** `where-is-my-bus.codefor.kr`(Rails 역할)와 `traccar-where-is-my-bus.codefor.kr`(Traccar 쪽)를 같은 443에 배포하니 SNI별로 각자의 인증서를 내보냈고(`subject=CN=<그 이름>`), 요청이 각 서비스로 갔다. 이름에 맞지 않는 인증서로 검증하면 실패(curl 종료코드 60)하고, 등록하지 않은 이름은 연결이 되지 않는다. 등록한 호스트가 아닌 요청은 404였다(앞선 실험).
2. **Traccar 5055는 등록되지 않은 기기의 요청에 어떤 경로든 400**이고(`/`, `/up`, 모르는 `id`), **등록된 기기의 위치 요청은 200**이다.
3. **헬스체크 문제 — 기기를 등록하고 쿼리 경로로 헬스체크하는 방법은 동작하지 않는다(이전 추천 철회).** kamal-proxy가 헬스체크 경로의 `?`를 `%3F`로 바꿔 `GET /%3Fid=healthcheck&lat=0&lon=0`으로 보낸다. 가짜 수신기에 도착한 요청 줄로 확인했다. 그래서 `target failed to become healthy`로 배포가 실패한다. kamal-proxy에는 헬스체크를 다른 포트(8082)로 돌리는 `--health-check-port`가 있고 동작하지만, **Kamal 2.11 설정에는 이 항목이 없다**(`healthcheck`는 `path`, `interval`, `timeout`만, 소스 확인).
4. **Traccar 앞에 nginx를 두는 방법은 동작한다.** nginx가 `/up`에는 직접 200을 주고 나머지는 Traccar 5055로 넘긴다(`resolver 127.0.0.11`과 변수 `proxy_pass`를 써서 Traccar가 아직 없어도 nginx가 부팅한다). kamal-proxy가 nginx(80)를 기본 헬스체크(`/up`)와 TLS로 배포하는 데 성공했고, HTTPS 위치 요청이 등록된 기기에 200, 미등록 기기에 400이다. Traccar를 멈추면 요청은 응답 없이 끝나고(8초 제한으로 시험) nginx 컨테이너는 살아 있으며, Traccar를 다시 켜면 곧바로 200으로 돌아온다. nginx 메모리는 약 9.7 MiB, 이미지는 약 50 MB다.
5. **평문 HTTP(80) 요청은 TLS 이름에서 301로 HTTPS로 리다이렉트**된다(`Location: https://...`, 기본값 `--tls-redirect` 켜짐). Kamal에서는 `proxy.ssl_redirect: false`로 끌 수 있다(소스 확인). 끈 상태의 동작은 시험하지 못했다. 앱 SDK가 리다이렉트를 따라가는지도 모르므로 앱 주소는 처음부터 `https://`로 준다.
6. Kamal 설정으로 이 구성이 풀린다(초안 아래): Traccar accessory는 `port=nil`, `proxy?=false`, nginx accessory는 `proxy?=true`, `hosts=["traccar-where-is-my-bus.codefor.kr"]`, `app_port=80`, `ssl=true`, `health-check-path=/up`.

### HTTPS 전환 체크리스트 (후속, 필수)

1. **DNS**: Cloudflare에 `traccar-where-is-my-bus.codefor.kr` DNS 전용(프록시 끔) A 레코드를 Rails와 같은 IP로 만들고, `dig +short`로 서버 IP를 확인한다(발급 전 선행 조건, 아래 "Let's Encrypt").
2. **`deploy.yml`**: `traccar-proxy`(nginx) accessory와 `config/traccar-nginx.conf`를 추가하고, `traccar` accessory의 `port: "5055:5055"`를 지우고, `TRACCAR_SERVER_URL`을 `https://traccar-where-is-my-bus.codefor.kr`로 바꾼다(아래 초안).
3. **보안 그룹**: 5055를 닫는다. 80과 443은 이미 연다.
4. **앱**: 평문 허용 목록(Android `network_security_config.xml`, iOS `Info.plist`)을 걷어낸다. 서브도메인으로 바꾸면 **웹 서버 이름에는 평문이 허용되지 않는다.**
5. **기사 폰 재등록**: 위치 전송 주소는 PIN 등록 때 폰에 저장된다. 평문 주소로 등록한 폰은 PIN을 재발급해 다시 등록해야 한다. 앱이 시작할 때 주소를 다시 받아 오게 하면 이 재등록이 필요 없어진다(앱과 Rails 변경, 후속 개선).
6. **확인**: 첫 배포 후 확인 절차를 HTTPS 기준으로 다시 한다(`curl -sI https://traccar-where-is-my-bus.codefor.kr/up`, Traccar 이벤트가 Rails에 200으로 도착).

### 왜 nginx를 쓰는가

nginx는 **Traccar 때문에만 필요하다.** Rails 앱에는 필요 없다(Rails에는 `/up`이 있어 kamal-proxy의 기본 헬스체크를 그대로 통과한다). 그리고 **TLS를 위해서가 아니라 kamal-proxy의 헬스체크를 통과시키기 위해서만** 쓴다. TLS 종단과 인증서 발급은 계속 kamal-proxy가 한다. 위치 수신을 HTTPS로 받지 않고 평문 5055를 그대로 둔다면 nginx도 필요 없다.

- kamal-proxy는 배포할 때 대상이 헬스체크에서 2xx를 줘야 트래픽을 넘긴다(통과하지 못하면 `target failed to become healthy`로 배포가 실패한다).
- Traccar 위치 수신 포트(5055)는 등록된 기기의 위치 요청에만 200을 주고 **그 밖의 모든 요청에 400**이다. 헬스체크용 경로가 없다(로컬 확인).
- 등록된 기기로 쿼리를 붙여 헬스체크하려 해도 kamal-proxy가 `?`를 `%3F`로 바꿔 보낸다(로컬 확인).
- 헬스체크를 다른 포트(8082)로 돌리는 kamal-proxy 옵션이 있지만 Kamal 2.11 설정에는 없다(소스 확인).

그래서 `/up`에는 직접 200을 주고 나머지를 Traccar 5055로 넘기는 얇은 앞단이 필요하다. nginx는 그 역할을 하는 여러 도구 중 하나이고, 설정이 짧고 이미지가 널리 쓰여 골랐다. 다른 도구(Caddy, HAProxy 등)는 시험하지 않았다.

- **드는 것**: 컨테이너 하나(메모리 약 10 MiB), 이미지 약 50 MB, 설정 파일 하나(`config/traccar-nginx.conf`). Traccar가 꺼져 있으면 위치 요청은 응답 없이 끝난다(앱의 큐가 쌓아 두었다 다시 보낸다).
- **nginx 없이 하는 방법**: 프록시 없이 평문 5055(HTTPS 요구사항에 어긋난다), 또는 `kamal-proxy deploy`를 `--health-check-port 8082`로 수동 호출(재현성이 낮다). 아래 표를 본다.

### 헬스체크 해법 비교

| 방법 | 상태 |
|---|---|
| **A. nginx 앞단 accessory (추천)** | 로컬에서 동작 확인. Kamal 설정 안에서 해결되고 재배포·재시작이 Kamal 방식 그대로다. 컨테이너가 하나 늘고(약 10 MiB) nginx 설정 파일이 하나 는다 |
| B. 기기 `healthcheck` + 쿼리 경로 | **동작하지 않음**(`?`가 `%3F`로 바뀜) |
| C. `kamal-proxy deploy`를 수동으로 호출해 `--health-check-port 8082` | 프록시 쪽은 동작. Kamal이 모르는 수동 단계라 재현성이 낮고 `kamal accessory boot`/`proxy reboot`와 충돌할 수 있다. 시험하지 못함 |
| D. 같은 이름 + 경로(`/osmand`) | 프록시 수준에서는 되지만(앞선 실험) 헬스체크 문제는 그대로이고 앱 SDK의 경로 처리를 모른다 |

### `deploy.yml` 초안 (적용 전)

```yaml
accessories:
  traccar:                          # 기존 설정에서 port "5055:5055"를 뺀다. 프록시도 없다
    image: traccar/traccar:6.14.4
    host: web01.where-is-my-bus
    env: ...                        # 지금과 같다
    volumes: [ ... ]
  traccar-proxy:                    # 컨테이너 이름 where-is-my-bus-traccar-proxy
    image: nginx:1.27-alpine
    host: web01.where-is-my-bus
    files:
      - config/traccar-nginx.conf:/etc/nginx/conf.d/default.conf
    proxy:
      host: traccar-where-is-my-bus.codefor.kr
      ssl: true
      app_port: 80
      healthcheck:
        path: /up
```

```nginx
# config/traccar-nginx.conf
server {
  listen 80;
  access_log off;
  location = /up { return 200 "ok"; }
  location / {
    resolver 127.0.0.11 valid=10s;
    set $upstream http://where-is-my-bus-traccar:5055;
    proxy_pass $upstream;
    proxy_set_header Host $host;
  }
}
```

- 보안 그룹은 22(관리자 IP만), 80, 443만 연다. **5055는 열지 않는다.** Rails와 nginx와 Traccar는 같은 도커 네트워크(`kamal`) 안에서 통신한다.
- `TRACCAR_SERVER_URL`은 `https://traccar-where-is-my-bus.codefor.kr`로 바꾼다. **앱 SDK는 `serverUrl`을 그대로 쓰고 HTTPS로 POST 폼을 보낸다**(SDK 소스 확인, [traccar-integration.md](traccar-integration.md) "운전자 앱의 위치 전송"). SDK와 같은 형식의 HTTPS POST가 프록시(TLS) → nginx → Traccar → 지오펜스 이벤트까지 통하는 것을 로컬에서 확인했다. **Let's Encrypt 인증서는 Android 7.1.1 이상에서만 신뢰된다**(Android 7.0 폰은 보내지 못한다).
- Traccar가 Rails로 보내는 이벤트(`http://rails-app:80/...`)와 Rails가 Traccar API를 부르는 주소(`http://where-is-my-bus-traccar:8082`)는 그대로다.

### Let's Encrypt 인증서를 받을 수 있는가

**조건이 맞으면 가능할 것으로 본다. 실제 발급은 시험하지 못했으므로 첫 배포에서 확인한다.**

- kamal-proxy는 Let's Encrypt용 `golang.org/x/crypto/acme/autocert`를 내장한다(바이너리에서 확인, `http-01` 문자열 포함). 그래서 **80과 443이 모두 인터넷에서 닿아야** 한다(HTTP-01 검증은 80). `proxy.host`에 이름을 적어 둔 호스트만 발급한다(`host not configured in HostWhitelist`). 인증서 캐시는 Kamal이 마운트하는 `kamal-proxy-config` 볼륨에 남는다.
- **두 이름 모두 발급 전에 같은 IP로 해석돼야 한다.** 현재 두 이름 모두 DNS 레코드가 없다(2026-11-01 조회). Cloudflare에서 두 이름 모두 **DNS 전용(프록시 끔)** A 레코드로 만든다(같은 IP). 하나만 `CNAME`으로 다른 이름을 가리키게 해도 된다.
- **`codefor.kr`에 CAA 레코드가 없다**(`codefor.kr`와 두 이름 모두 비어 있음, 2026-11-01 조회). 그래서 인증서 발급 기관을 제한하지 않고 Let's Encrypt가 막히지 않는다. `codefor.kr`은 DNSSEC을 쓴다(DS 레코드 있음). 존이 Cloudflare 관리라 영향이 없을 것으로 보지만 확인하지 못했다.
- **발급 속도 제한(Let's Encrypt 공식 문서, 2026-11-01 확인)**: `codefor.kr` 전체가 하나의 "등록 도메인"이라 **일주일에 인증서 50개를 이 도메인의 모든 하위 이름이 나눠 쓴다**(다른 팀이 `codefor.kr` 하위 이름으로 발급한 것도 센다). 이 서비스는 2개를 쓴다. 같은 이름 조합은 일주일에 5개, **이름별 인증 실패는 시간당 5번**이다. 실패 제한은 DNS가 맞기 전에 배포를 반복하면 걸리니, **DNS가 맞는 것을 확인한 뒤에 배포**한다(`dig +short <이름>`이 서버 IP와 같은지).
- **스테이징으로 먼저 시험할 수 없다.** kamal-proxy에는 `--tls-staging`이 있지만 Kamal 2.11 설정에는 이 옵션이 없다(소스 확인). 실패 제한이 부담되면 `kamal-proxy`를 직접 호출해 시험해야 한다.
- **첫 배포 순서 제안**: ① 서버 생성과 Elastic IP, 보안 그룹 80·443 ② Cloudflare에서 두 이름의 DNS 전용 A 레코드 ③ `dig`로 두 이름이 서버 IP를 가리키는지 확인 ④ `bin/deploy setup` ⑤ `bin/kamal proxy logs`로 발급 로그를 보고 `curl -sI https://<이름>/up`으로 확인.
- **확인하지 못한 것**: 실제 발급, 두 이름의 연속 발급, 갱신(만료 전 자동 갱신은 autocert가 한다고 알고 있다), 서버가 오래 꺼져 있다 켜질 때의 인증서 상태.

## 위치 수신 주소: 도메인을 하나 더 두는가

**결론: 둔다.** 위치 수신용 이름을 승객 사이트와 분리한다. 제안: `traccar-where-is-my-bus.codefor.kr` (Cloudflare에서 **DNS 전용(프록시 끔)**, 값은 `where-is-my-bus.codefor.kr`을 가리키는 CNAME 또는 같은 IP의 A 레코드). 비용은 DNS 레코드 하나이고 HTTP에는 인증서가 필요 없다.

위치 수신이 HTTP(평문, 5055)인 한 아래 이유가 겹친다. 도메인 없이 `http://where-is-my-bus.codefor.kr:5055`로 써도 **동작은 한다.** 분리하는 이유는 동작이 아니라 보안과 나중에 바꾸는 비용이다.

### 이름 형태: `traccar-where-is-my-bus`(하이픈)와 `traccar.where-is-my-bus`(하위 도메인)

**둘 다 동작한다.** 이 구성(DNS 전용, 이름마다 kamal-proxy가 Let's Encrypt 인증서)에서는 어느 쪽을 써도 결과가 같고, 차이는 아래 네 가지다. **하이픈 이름을 추천한다.**

| | 하이픈 `traccar-where-is-my-bus.codefor.kr` | 하위 도메인 `traccar.where-is-my-bus.codefor.kr` |
|---|---|---|
| Let's Encrypt | 이름마다 발급. 속도 제한은 `codefor.kr` 전체로 계산 | 같음. 이름 깊이와 무관 |
| Cloudflare 프록시(주황 구름)로 바꿀 때 | Universal SSL이 루트와 **1단계** 하위 이름을 덮는다. **덮는다** | **2단계**라 Universal SSL이 덮지 않아 유효 인증서가 없다(문서: "not covered", 해결은 유료 Advanced Certificate Manager). 이 이름을 DNS 전용으로 두면 무관 |
| 브라우저 HSTS | Rails가 `Strict-Transport-Security: max-age=63072000; includeSubDomains`를 보낸다(운영 요청으로 확인). `where-is-my-bus.codefor.kr`의 **하위 이름 전부**가 브라우저에서 HTTPS 강제 대상이 된다 | 이 범위 안에 들어간다(브라우저만 해당, 앱 SDK는 HSTS를 쓰지 않음) |
| 쿠키 | 세션 쿠키에 `domain:` 지정이 없다(`authentication.rb`, 호스트 전용). 어느 이름이든 서로 전달되지 않는다 | 같음. 나중에 `domain:`을 지정하면 하위 이름으로 전달되므로 하이픈이 더 안전하다 |
| 정리·가독성 | 조직 존의 다른 이름(`testtraccar.codefor.kr`)처럼 한 단계 이름 | 프로젝트 이름 아래로 묶여 보이고 앱 도메인이 바뀌면 `traccar.<새 도메인>`으로 따라간다 |

- 하이픈을 추천하는 이유: Cloudflare 프록시로 옮길 여지가 남고, HSTS와 쿠키 범위가 앱과 완전히 분리된다. 하위 도메인은 정리 면에서 낫다.
- `where-is-my-bus.codefor.kr`에 A 레코드가 있어도 하위 이름을 따로 만드는 데는 문제가 없고, `codefor.kr`에는 와일드카드 레코드가 없다(임의 이름 조회가 비어 있음).

### 이유

1. **평문 허용 범위를 위치 수신 이름 하나로 좁힌다 (가장 큰 이유).** 운전자 앱은 평문을 도메인 단위로만 허용한다. Android `network_security_config.xml`은 `<domain>` 단위, iOS `NSExceptionDomains`도 도메인 단위이며 **포트로 구분하지 못한다**(플랫폼 동작, 이 저장소의 두 파일이 도메인만 적는 것을 확인함). 위치 수신이 승객 사이트와 같은 이름이면 그 이름을 평문 허용에 넣어야 하고, 그러면 같은 이름의 **HTTPS 웹 서버 호출(PIN 등록, 운행 시작·종료)** 도 OS가 막아 주지 않는다. 앱 입력란에 `http://`로 잘못 적어도 통과한다(`adminUrl`은 운전자가 입력한다). 이름을 나누면 **승객 사이트는 계속 HTTPS만** 허용되고 평문은 위치 수신 이름에만 열린다. 이 저장소가 이미 겪은 상황이다: 지금 허용 목록은 테스트 서버 한 도메인이고 Traccar와 웹이 같은 이름이다([future-improvements.md](future-improvements.md) 29번).
2. **Cloudflare 프록시와 충돌하지 않는다.** 승객 사이트를 나중에 Cloudflare 프록시(주황 구름, DDoS 방어·캐시)로 돌리고 싶어도, 프록시는 허용된 일부 포트만 전달하고 5055는 그 목록에 없는 것으로 알고 있다(Cloudflare 문서로 확인하지 못함). 이름이 같으면 승객 사이트를 영원히 DNS 전용으로 둬야 한다. 분리하면 `traccar.…`만 DNS 전용으로 두고 사이트는 프록시를 켤 수 있다.
3. **HTTPS로 올릴 때 이름을 나누는 쪽이 낫다.** kamal-proxy는 호스트 이름으로 요청을 나눈다. 같은 이름을 쓰려면 경로(`/osmand`)로 나눠야 하는데 프록시 수준에서는 되고(로컬 실험) SDK도 `serverUrl`을 경로째 그대로 쓰므로(SDK 소스 확인) 막히는 곳은 없다. 다만 경로로 나눠도 Traccar 헬스체크 문제(앞단 nginx 필요)는 그대로라 얻는 것이 적고 별도 이름이 더 단순하다. 자세한 비교는 아래 "위치 수신(5055)을 HTTPS로"를 본다.
4. **Traccar만 다른 서버로 옮길 수 있다.** 이름이 Traccar 전용이면 그 레코드만 바꾸면 된다. 이름을 공유하면 Traccar를 옮길 때 이름도 새로 만들어야 한다.

### 이 저장소에서 확인한 것 — 주소는 휴대폰에 박힌다

- Rails의 PIN 등록 응답이 `traccarServerUrl`(= `TRACCAR_SERVER_URL`)을 앱에 돌려준다(`integrations/traccar_controller.rb`).
- 앱은 그 값을 `SharedPreferences`에 저장하고(`driver_registration.dart`) Traccar SDK 초기화에 그대로 쓴다(`tracking_controller.dart`). **다시 받아 오는 코드는 없다.**

그래서 **지금 정하는 이름과 주소가 등록된 모든 기사 휴대폰에 저장된다.** 나중에 바꾸면 기사마다 PIN을 새로 받아 다시 등록해야 한다(PIN은 1회용, 관리자 "PIN 재발급"). 도메인을 나눌지 지금 정하는 편이 싼 이유다. 같은 이유로 HTTP → HTTPS 전환도 주소가 바뀌므로(`http://…:5055` → `https://…`) 도메인 분리와 별개로 **재등록 문제가 남는다.**

→ 후속 개선 제안: 앱이 시작할 때 `GET /integrations/traccar/bus`처럼 이미 쓰는 호출에서 `traccarServerUrl`을 다시 받아 저장하게 하면 주소를 바꿔도 재등록이 필요 없다. 이 변경은 Rails 응답과 앱 코드를 함께 고쳐야 해서 이번 범위에 넣지 않았다. 구현하려면 `driver-app` 스킬의 절차(로컬 `flutter test`·`flutter analyze`)가 필요하다.

### 분리했을 때 바뀌는 곳 (아직 적용하지 않았다)

| 파일 | 바꿀 값 |
|---|---|
| `config/deploy.yml` `env.clear.TRACCAR_SERVER_URL` | `http://traccar-where-is-my-bus.codefor.kr:5055` |
| Cloudflare DNS | `traccar-where-is-my-bus.codefor.kr` 레코드(DNS 전용). Elastic IP를 쓰는 동안은 A 레코드, 나중에 IP가 바뀌는 방식(4장 B·C)으로 가면 **CNAME으로 두어 한 곳만 갱신**한다 |
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

1. **위치 수신 HTTPS**: **보류, 필수 후속 작업**(2026-11-01). 첫 배포는 동작 확인을 위해 평문 5055로 한다. 전환 방식은 서브도메인 `traccar-where-is-my-bus.codefor.kr` + nginx(로컬 검증)로 정했고, 전환 체크리스트는 위 "HTTPS 전환 체크리스트". **승객 공개와 실운행 전에 한다.**
2. ~~도메인 검사 삭제~~ → **결정: 유지하되 소스에 직접 적는다**(적용됨). 환경변수화는 후속 작업.
3. 비밀번호 재설정 메일을 쓸지.
4. 서버 크기: **결정 `t4g.micro` + 스왑 2GB**([aws-server-operations.md](aws-server-operations.md) 6장).
5. 껐다 켜는 시간표(운행 시간). [aws-server-operations.md](aws-server-operations.md).
