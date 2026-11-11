# 운영 배포 (Kamal)

Rails 앱과 Traccar를 **한 서버**에 Kamal로 올린다. Traccar는 Kamal **accessory**(컨테이너 `where-is-my-bus-traccar`)다. 설계와 확인 내용은 [traccar-accessory.md](traccar-accessory.md).
도메인은 `where-is-my-bus.codefor.kr`이다. 이 도메인의 DNS 연결은 아직 하지 않았다(Cloudflare에 A 레코드를 만든다). 나중에 바꿀 수 있다 — "도메인 변경".

> 이 문서는 **아직 실제 서버에서 끝까지 실행해 보지 않았다.** 이미지 빌드, 빈 DB에서의 `db:prepare`, 이미지 내용 검사는 로컬에서 확인했고(아래 "로컬에서 확인한 것"), 서버 배포·인증서 발급은 첫 배포 때 확인한다. Traccar accessory의 이벤트 포워딩은 로컬 도커 네트워크에서 확인했다([traccar-accessory.md](traccar-accessory.md)).

## 구성

```
[한 서버]
운전자 앱 ──위치(5055)──▶ Traccar 컨테이너 ──Geofence 이벤트(X-Ingest-Token)──▶ http://rails-app:80/integrations/traccar/events
                            ▲                                                    │  (kamal 도커 네트워크 안, 서버 밖으로 안 나감)
                            └──── Rails가 http://where-is-my-bus-traccar:8082 호출(서비스 토큰) ◀┘
승객 ──▶ https://where-is-my-bus.codefor.kr  (kamal-proxy가 HTTPS 종단 → 컨테이너 80 → Thruster → Puma)
```

| 항목 | 값 | 위치 |
|---|---|---|
| 이미지 | GHCR `ghcr.io/code-for-korea/where-is-my-bus` (처음 **비공개**, 점검 뒤 공개) | `config/deploy.yml` `image`, `registry` |
| 서버 | Rails를 올릴 서버 1대 | `config/deploy.yml` `servers.web` |
| 데이터 | 호스트 `/var/lib/where-is-my-bus/storage` (컨테이너 밖) | `config/deploy.yml` `volumes` |
| 비밀값 | `config/credentials/production.yml.enc` (키: `production.key`) | Rails credentials |
| Traccar | 같은 서버의 accessory. 토큰은 배포 PC의 환경변수 `TRACCAR_API_TOKEN`, `TRACCAR_INGEST_TOKEN` | `config/deploy.yml` `accessories`, `.kamal/secrets` |
| Traccar 접속 설정 | 환경변수가 credentials보다 우선 | [traccar-integration.md](traccar-integration.md) |

`config/deploy.yml`의 서버는 IP가 아니라 SSH 별칭 `web01.where-is-my-bus`다(두 곳). IP와 접속 사용자는 배포 PC의 `~/.ssh/config`에 둔다(아래 "SSH 별칭").

## 첫 배포의 위치 수신은 임시로 평문(HTTP)이다 — HTTPS는 꼭 반영해야 한다

**결정(2026-11-01): 동작을 먼저 확인하려고 첫 배포는 위치 수신을 평문 HTTP 5055로 했다. 2026-11-03에 `traccar-proxy`(nginx)를 올려 HTTPS 이름이 응답하는 것까지 확인했고, 앱 주소 전환과 폰 재등록 뒤 평문 게시를 닫는다([traccar-accessory.md](traccar-accessory.md) 맨 위).** 운전자 앱은 `http://where-is-my-bus.codefor.kr:5055`로 위치를 보내고(`TRACCAR_SERVER_URL`, Traccar accessory가 5055를 게시), Rails 사이트(443)는 처음부터 HTTPS다. **HTTPS는 필수 후속 작업이고 보류일 뿐 생략이 아니다.** nginx도 그때까지 쓰지 않는다.

**HTTPS로 보호해야 하는 이유**
- 위치와 `deviceId`가 **암호화되지 않고** 오간다. `deviceId`는 운행 시작·종료 API의 사실상 비밀번호다(`AGENTS.md` 함정 6, `docs/future-improvements.md` 2번).
- 5055는 **인터넷 전체에 열려 있다**(기사 폰이 이동통신망이라 출발 IP를 좁힐 수 없다). 네트워크에서 엿본 사람은 그 버스의 `deviceId`를 알아내 **운행을 시작·종료하거나 가짜 위치를 보낼 수 있다.** HTTPS는 엿보기를 막지만 알아맞히기는 막지 못한다.
- 그래서 평문은 **시험(소수의 기기, 실운행 전)에만** 쓴다. **승객에게 공개하기 전, 실운행 전에 HTTPS로 전환한다.**

**이 임시 구성에서 꼭 알아야 할 것**
- **앱의 평문 허용 목록에 `where-is-my-bus.codefor.kr`를 넣은 앱 빌드가 필요하다.** 휴대폰 OS는 `http://` 접속을 기본으로 막는데 지금 허용 목록에는 옛 테스트 서버(`yehyunserver.iptime.org`)뿐이다. 시험하는 사람이 **자기 로컬에서만** 추가하고 커밋하지 않는다(`docs/future-improvements.md` 29번 방침): Android `driver_app/android/app/src/main/res/xml/network_security_config.xml`의 `<domain>`, iOS `driver_app/ios/Runner/Info.plist`의 `NSExceptionDomains`. 추가한 뒤 앱을 다시 빌드한다.
- **이 허용은 도메인 단위라 포트를 구분하지 못한다.** 그래서 **같은 이름의 웹 서버(HTTPS 사이트)에도 평문이 허용**된다. 앱의 `adminUrl` 입력은 스킴이 없으면 `http://`를 붙이므로(`driver_app/lib/api_client.dart`), **`adminUrl`은 반드시 `https://where-is-my-bus.codefor.kr`로 직접 입력한다.** 그렇지 않으면 PIN과 `deviceId`가 평문으로 나가고, 서버가 301로 HTTPS로 돌려보내기 전에 이미 요청이 나간 뒤다. 이 위험은 위치 수신에 **별도 이름**을 쓰면 사라진다(아래 후속 작업).
- 보안 그룹에서 **5055를 열어야** 한다(HTTPS 전환 후 닫는다).
- **평문 주소로 등록한 폰은 나중에 다시 등록해야 한다.** 위치 전송 주소는 PIN 등록 때 폰에 저장되고 다시 받아 오지 않는다(`docs/traccar-integration.md`). HTTPS로 바꾸면 주소가 달라지므로, 임시 평문으로 등록한 폰이 많을수록 재등록이 늘어난다. 시험 폰을 적게 유지한다.

**HTTPS 전환 계획 (필수, 후속)**: 위치 수신에 **서브도메인 `traccar.where-is-my-bus.codefor.kr`**를 쓴다. Rails와 같은 IP(Cloudflare DNS 전용 A 레코드)로 연결하고, Traccar 앞에 nginx(헬스체크용), kamal-proxy가 443에서 TLS와 Let's Encrypt 인증서를 맡는다. 설계, 로컬 검증 결과, 인증서 발급 조건은 [traccar-accessory.md](traccar-accessory.md)의 "위치 수신(5055)을 HTTPS로". 전환할 때 할 일:
1. Cloudflare에 `traccar.where-is-my-bus.codefor.kr`와 `admin.traccar.where-is-my-bus.codefor.kr` DNS 전용 A 레코드를 만들고 `dig`로 서버 IP를 확인한다.
2. `deploy.yml`에 `traccar-proxy`(nginx) accessory와 `config/traccar-nginx.conf`를 추가하고, Traccar accessory의 `port: "5055:5055"`를 지우고, `TRACCAR_SERVER_URL`을 `https://traccar.where-is-my-bus.codefor.kr`로 바꾼다.
3. 보안 그룹에서 5055를 닫고 앱의 평문 허용을 걷어낸다.
4. 기사 폰을 다시 등록한다(PIN 재발급).

## 배포 전 준비 (한 번만)

### 1. DNS·서버
- `where-is-my-bus.codefor.kr`의 A 레코드를 Rails 서버 IP로 만든다. Let's Encrypt 발급이 이 레코드를 필요로 하므로 `dig +short where-is-my-bus.codefor.kr`로 먼저 확인한다.
- 서버 구성(`t4g.micro` + 스왑 2GB, Elastic IP 권장)과 가격은 [server-spec.md](server-spec.md), Ubuntu 설치 절차는 [server-setup-ubuntu.md](server-setup-ubuntu.md)를 본다.
- 서버에 Docker를 설치하고, 배포하는 PC에서 SSH로 접속할 수 있어야 한다(배포 사용자가 `docker` 그룹). 방화벽에서 80/443을 연다.

#### SSH 별칭
`deploy.yml`은 서버를 `web01.where-is-my-bus`로 부른다. Kamal이 쓰는 Net::SSH가 `~/.ssh/config`를 읽어 별칭을 실제 주소로 풀어내는 것을 확인했다. **배포하는 PC마다** 아래 항목이 있어야 한다. 서버 IP나 사용자가 바뀌어도 `deploy.yml`은 고치지 않는다.

```
Host web01.where-is-my-bus
  HostName <서버 IP 또는 Elastic IP>
  User ubuntu
  IdentityFile ~/.ssh/<키 파일>
```

- `ssh web01.where-is-my-bus docker ps`가 비밀번호 없이 되는지 먼저 확인한다.
- 접속 사용자는 `deploy.yml`의 `ssh.user: ubuntu`로 정한다. `deploy.yml`의 값이 `~/.ssh/config`의 `User`보다 우선하므로 config의 `User`는 생략해도 된다(두 값은 같게 둔다).
- 별칭은 PC별 설정이라 저장소에 없다. 새 배포자는 이 항목을 직접 만들어야 한다.
- 방화벽(보안 그룹)에서 **5055**(운전자 앱의 위치 전송)도 연다. Traccar 웹(**8082**)도 임시로 열되 **관리자 IP로만** 제한한다(HTTPS + 브라우저 인증으로 옮기면 닫는다, [traccar-accessory.md](traccar-accessory.md) "이름과 구성"). 서버를 새로 만들고 Traccar는 이 서버에서만 돈다. 80/443을 쓰는 다른 프록시가 없는 서버여야 한다.
- `deploy.yml`의 `servers.web.hosts`와 `accessories.traccar.host`에 같은 서버를 적는다.

### 2. 호스트 데이터 디렉터리
`storage/`에는 SQLite 4개(`production`, `production_cache`, `production_queue`, `production_cable`)와 Active Storage 파일이, `traccar/`에는 Traccar의 H2 DB가 쌓인다. 컨테이너는 uid 1000(`rails`)으로 돌기 때문에 권한이 필요하다. **빼먹으면 `db:prepare`가 실패해 컨테이너가 뜨지 않는다.**

```bash
sudo mkdir -p /var/lib/where-is-my-bus/storage /var/lib/where-is-my-bus/traccar
sudo chown 1000:1000 /var/lib/where-is-my-bus/storage      # Rails(uid 1000). traccar 디렉터리는 컨테이너가 root라 불필요
sudo mkdir -p /var/backups/where-is-my-bus
sudo apt install -y sqlite3        # bin/backup-storage가 쓴다
```

### 3. 레지스트리: GHCR (처음 비공개, 나중에 공개)
- `deploy.yml`은 `ghcr.io/code-for-korea/where-is-my-bus`를 쓴다. 첫 push 때 패키지가 **비공개**로 만들어지고, `Dockerfile`의 `org.opencontainers.image.source` 라벨로 이 저장소에 연결된다.
- **클래식 PAT**를 만든다(GitHub > Settings > Developer settings > Tokens (classic)). 권한은 `write:packages`(받기만 하는 서버용이면 `read:packages`). 이 조직에 SSO가 걸려 있으면 토큰을 조직에 승인(Authorize)해야 한다.
- 사용자 이름은 **GitHub 사용자 이름**이다. `bin/deploy`가 `.env.deploy` 파일(아래 "배포 값 파일")이나 환경변수에서 읽고, 없으면 **gh 로그인**을 쓰고(아래), 그것도 없으면 실행할 때 입력받는다(토큰은 화면에 보이지 않는다). `.kamal/secrets`는 환경변수를 참조만 한다.
- 비공개 패키지라도 Kamal이 서버에 같은 토큰으로 로그인해 이미지를 받으므로 서버에 따로 할 일은 없다.
- 첫 push 뒤 패키지 화면(조직 Packages)에서 저장소 연결과 접근 권한을 확인한다. Actions 등 다른 곳에서 받을 일이 없으면 그대로 둔다.
- **공개로 바꾸기**: 이미지 내용 점검("이미지에 넣지 않는 것")을 마친 뒤 패키지 설정 "Danger Zone"에서 공개로 바꾼다. **한 번 공개하면 비공개로 되돌릴 수 없다.** 조직 소유자가 공개 패키지 생성을 막았으면 설정 > Packages에서 풀어야 한다(확인하지 못함). 공개한 뒤에는 서버가 로그인 없이 받을 수 있지만 Kamal은 배포 때 로그인하므로 `bin/deploy` 사용은 그대로다.
- 비공개 패키지의 무료 한도는 GitHub 문서 기준 확인이 필요하다(아래 "이미지 크기와 레지스트리 무료 한도"). 이미지는 gzip 약 185MB다.

#### GHCR 검토 결과 (적용함)

GitHub의 `ghcr.io`도 공개 이미지에 무료로 쓸 수 있다(공식 문서: "공개 패키지 사용은 무료", 컨테이너 레지스트리의 저장·대역폭은 "현재 무료"이며 정책 변경 시 최소 1개월 전에 공지).

```yaml
image: code-for-korea/where-is-my-bus     # 소문자여야 한다
registry:
  server: ghcr.io
  username:
    - KAMAL_REGISTRY_USERNAME             # GitHub 사용자 이름
  password:
    - KAMAL_REGISTRY_PASSWORD             # 클래식 PAT(write:packages)
```

- Kamal이 이미지를 `ghcr.io/code-for-korea/where-is-my-bus:<버전>`으로 풀어내는 것을 확인했다. 대문자 이름(`Code-for-Korea`)은 Kamal이 받아도 Docker가 `repository name must be lowercase`로 거부한다(확인함).
- **토큰은 클래식 PAT만 지원**한다(문서에 Fine-grained 토큰 언급이 없다). 권한은 `write:packages`다. 이 PC의 GitHub 로그인에는 이 권한이 없다(`gist`, `read:org`, `repo`, `workflow`).
- **처음 올린 패키지는 비공개**이고 패키지 설정의 "Danger Zone"에서 공개로 바꾼다. **한 번 공개하면 비공개로 되돌릴 수 없다.** 비공개 상태에서 이미지를 받아 "이미지에 넣지 않는 것" 점검을 한 뒤 공개로 바꿀 수 있다는 점이 Docker Hub(올리는 순간 공개)와 다르다.
- 조직 소유자가 설정 > Packages에서 구성원의 공개 패키지 생성을 막을 수 있다. 이 조직의 설정은 확인하지 못했다.
- `Dockerfile`에 `org.opencontainers.image.source` 라벨이 있으면 패키지가 저장소와 연결되어 저장소의 접근 권한을 이어받는다(공개 여부는 이어받지 않는다). 지금은 라벨이 없다.
- **토큰 위험**: 클래식 PAT의 `write:packages`는 그 사용자가 쓸 수 있는 모든 패키지에 걸린다. 유출되면 운영 이미지를 덮어써서 Kamal이 그대로 배포하게 만들 수 있다. 개인 계정 대신 전용 봇 계정을 쓰는 것이 낫다. Kamal은 서버에도 같은 토큰으로 로그인하므로(push 권한이 서버의 Docker 설정에 남는다) Docker Hub도 같다. PAT는 사람 계정에 묶여서 그 사람이 조직을 떠나면 배포가 막힌다.
- 확인하지 못함: 당겨받기 횟수 제한(문서에 언급 없음).

### 4. 운영 credentials 만들기
**`.gitignore`가 `/config/credentials/*.key`를 막는지 먼저 확인한 뒤** 만든다(막지 않으면 `git add -A`로 키가 커밋된다).

```bash
git check-ignore -v config/credentials/production.key   # 무시 규칙이 출력돼야 한다
bin/rails credentials:edit --environment production
```

편집기에 넣을 값:

```yaml
secret_key_base: <자동 생성된 값 그대로>
site_url: https://where-is-my-bus.codefor.kr
```

- Traccar 값(`traccar.*`)은 credentials에 **넣지 않는다.** `deploy.yml`의 환경변수가 우선하고 토큰은 배포 PC의 환경변수에서 Rails와 Traccar 양쪽으로 내려간다(아래 5). credentials에 옛 값이 남아 있으면 헷갈리므로 비워 둔다.
- `config/credentials/production.key`를 **비밀번호 관리자 등에 백업**한다. 잃으면 `production.yml.enc`를 열 수 없다. git·이미지에는 들어가지 않는다(`.gitignore`, `.dockerignore`).
- `production.yml.enc`는 암호문이라 커밋해도 되고 이미지에도 들어간다. 저장소가 공개이므로 안전성은 `production.key`에 달려 있다. 키가 유출되면 `credentials:edit`로 키를 다시 만들고 토큰도 바꾼다.

### 5. Traccar 토큰 (배포 PC의 환경변수)
토큰 두 개를 **새로** 만들어 배포하는 PC의 환경변수로 둔다. 같은 값이 Rails와 Traccar 컨테이너에 함께 들어간다.

```bash
export TRACCAR_API_TOKEN=$(openssl rand -hex 32)      # Rails가 Traccar API를 부를 때 (Traccar의 서비스 토큰)
export TRACCAR_INGEST_TOKEN=$(openssl rand -hex 32)   # Traccar가 Rails에 이벤트를 보낼 때 (X-Ingest-Token)
bin/kamal secrets print | sed -E 's/(RAILS_MASTER_KEY|KAMAL_REGISTRY_PASSWORD)=.*/\1=<숨김>/'   # 값이 풀리는지 확인
```

| 어디서 | 값 |
|---|---|
| Rails `TRACCAR_API_TOKEN` ↔ Traccar `WEB_SERVICE_ACCOUNT_TOKEN` | 같은 값(`.kamal/secrets`가 파생) |
| Rails `TRACCAR_INGEST_TOKEN` ↔ Traccar `EVENT_FORWARD_HEADER` | `X-Ingest-Token: <같은 값>` |

- **토큰을 비밀번호 관리자에도 보관한다.** 배포 PC를 바꾸면 같은 값을 다시 넣어야 하고, 값이 달라지면 Rails ↔ Traccar가 끊긴다.
- 로컬 데모 토큰(`dev-traccar-*`)은 공개 저장소에 있으므로 **운영에서 쓰지 않는다.** 쓰거나 값이 비어 있으면 앱이 부팅하지 않는다(`TraccarProductionCheck`).
- Traccar 설정은 `traccar.xml` 없이 `deploy.yml`의 환경변수로 한다(`web.registration`은 꺼 둔다). 환경변수 이름 규칙, 포워딩 확인 결과, 남은 위험은 [traccar-accessory.md](traccar-accessory.md).
- Rails는 서비스 토큰으로 Traccar를 부르므로 **Rails 동작에는 Traccar 계정이 필요 없다.** 사람이 Traccar 관리 화면에 들어갈 때만 계정이 필요하다. 관리 화면은 `https://admin.traccar.where-is-my-bus.codefor.kr`(브라우저 인증 뒤 Traccar 로그인, [traccar-accessory.md](traccar-accessory.md) "이름과 구성")이고, 임시 8082는 보안 그룹에서 관리자 IP로만 열려 있다. `WEB_REGISTRATION=false`라 화면에서 가입할 수 없으므로 **서버에서 `traccar:create_admin`으로 만든다**(아래 "Traccar 관리자 계정 만들기").

## 이미지에 넣지 않는 것 (공개 이미지)

공개 이미지(공개로 바꾼 뒤의 GHCR 포함)는 누구나 받아서 내용을 볼 수 있고, 한 번 올린 것은 회수할 수 없다. `.dockerignore`가 아래를 막는다.

- 키: `.env*`, `config/master.key`, `config/credentials/*.key`
- 개발용 credentials 암호문 `config/credentials.yml.enc` (운영은 `production.yml.enc`만 쓴다)
- 개발 DB·로그·임시 파일(`storage/*`, `log/*`, `tmp/*`), `.git`, `.github`, `.kamal`, `config/deploy*.yml`, `Dockerfile*`
- 에이전트·IDE 디렉터리(`.claude`, `.agents`, `.omc`, `.omo`, `.ruby-lsp`)
- 개발 문서·테스트·로컬 데모 구성(`docs`, `test`, `script`, `docker`, `compose.yaml`, `AGENTS.md`, `README.md`)
- `driver_app/`

Kamal은 로컬 작업 폴더가 아니라 git에 커밋된 내용으로 이미지를 만든다(미커밋 파일은 들어가지 않음). `.dockerignore`는 로컬에서 직접 `docker build`를 해도 안전하도록 이중으로 둔다.

**push 전에 이미지 내용을 직접 확인한다.** 이 결과에서 하나라도 나오면 올리지 않는다.

```bash
docker build -t where-is-my-bus:check .
docker run --rm --entrypoint sh where-is-my-bus:check -c '
  ls -A /rails
  find /rails -type f \( -name "*.key" -o -name ".env*" -o -name "*.sqlite3*" -o -name "settings.local.json" -o -name "credentials.yml.enc" \)
  for d in docs test script docker .claude .agents .omc .omo AGENTS.md README.md compose.yaml; do [ -e /rails/$d ] && echo "남아 있음: $d"; done'
docker history --no-trunc where-is-my-bus:check --format '{{.CreatedBy}}' | grep -i -E "ENV|ARG"   # 비밀값이 없어야 한다
```

## 배포 값 파일 (`.env.deploy`)

`bin/deploy`는 프로젝트 루트의 `.env.deploy`에서 배포에 쓰는 값 네 개를 읽는다. 형식은 `.env`와 같다.

```
KAMAL_REGISTRY_USERNAME=<GitHub 사용자 이름>
KAMAL_REGISTRY_PASSWORD=<클래식 PAT>
TRACCAR_API_TOKEN=<openssl rand -hex 32>
TRACCAR_INGEST_TOKEN=<openssl rand -hex 32>
TRACCAR_ADMIN_HTPASSWD='admin:$apr1$...'   # Traccar 관리 화면 브라우저 인증. 만드는 법은 docs/traccar-accessory.md "계정 값 만들기"
```

- **우선순위**: 이미 있는 환경변수 > `.env.deploy` > **gh 로그인** > 입력 프롬프트. 레지스트리 값(`KAMAL_REGISTRY_*`)은 위에서부터 채워지는 것을 쓰고, 그래도 없으면 묻는다.
- **읽는 이름은 위 다섯 개뿐이다.** 다른 이름은 경고하고 무시한다. 파일은 `source`하지 않고 한 줄씩 읽어서 값 안의 `$(...)` 같은 문자열이 실행되지 않는다(확인함). 앞뒤 공백과 따옴표(`"`, `'`)는 벗긴다.
- **`.env`가 아니라 `.env.deploy`인 이유**: `docker compose`가 `.env`를 자동으로 읽어 로컬 데모 설정(`TRACCAR_SERVER_URL`, `RAILS_PORT`)과 섞인다. `/.env*`가 `.gitignore`와 `.dockerignore`에 있어 `.env.deploy`도 git과 이미지에 들어가지 않는다. 다른 위치를 쓰려면 `DEPLOY_ENV_FILE=<경로> bin/deploy`.
- **`chmod 600 .env.deploy`**. 다른 사용자가 읽을 수 있으면 경고한다. 이 파일에는 레지스트리 토큰과 운영 토큰이 평문으로 있으므로 비밀번호 관리자에도 보관한다.
- `bin/kamal`을 직접 실행하면 이 파일을 읽지 않는다. 배포는 `bin/deploy`로 한다.

### gh(GitHub CLI) 로그인으로 레지스트리 인증

`KAMAL_REGISTRY_PASSWORD`가 환경변수와 `.env.deploy`에 없고 `gh`가 로그인되어 있으면, `bin/deploy`가 `gh auth token`을 토큰으로, 로그인한 GitHub 계정을 사용자 이름으로 쓴다(`KAMAL_REGISTRY_USERNAME`이 있으면 그 이름을 쓴다).

- **`write:packages` 권한이 필요하다.** `bin/deploy`가 토큰의 권한을 먼저 확인하고 없으면 서버에 접속하기 전에 멈춘다. 권한은 `gh auth refresh -h github.com -s write:packages`로 추가한다(브라우저 인증).
- **서버의 Docker 설정에 토큰이 남는다.** Kamal이 서버에서도 같은 토큰으로 `docker login`을 하기 때문이다. `gh` 토큰은 `repo` 등 권한이 넓어서, 서버가 뚫리면 그 범위가 노출된다. 서버에 남기는 토큰의 범위를 줄이려면 `write:packages`만 가진 클래식 PAT을 `.env.deploy`에 두면 된다(우선순위가 gh보다 높다).
- `gh` OAuth 토큰(`gho_…`)으로 GHCR 로그인이 되는지는 실제 로그인으로 확인한다: `gh auth token | docker login ghcr.io -u <이름> --password-stdin`. 안 되면 클래식 PAT을 쓴다.
- 동작은 스텁한 `gh`로 확인했다(권한 없음 → 안내 후 종료, 권한 있음 → 계정·토큰 사용, 환경변수가 있으면 gh를 쓰지 않음). 실제 GHCR 로그인은 확인하지 못했다.

## 첫 배포

```bash
# 위 5. Traccar 토큰과 레지스트리 값을 .env.deploy에 둔다(아래 "배포 값 파일"). 없으면 환경변수로 export하고 프롬프트로 입력한다.
bin/deploy setup           # 파일에 없는 레지스트리 사용자 이름·토큰은 묻는다. 서버 준비, Traccar accessory 기동, 이미지 빌드·push, Rails 컨테이너 기동, 인증서 발급
bin/kamal accessory details traccar   # Traccar가 떠 있는지
bin/kamal app logs         # 부팅 로그
```

`TRACCAR_ADMIN_HTPASSWD`(Traccar 관리 화면의 브라우저 인증, `docs/traccar-accessory.md` "이름과 구성")는 `setup`과 `accessory` 명령 앞에서 확인한다. `bin/deploy`는 `deploy`·`setup`·`redeploy` 앞에서 `config/credentials/production.key`와 `TRACCAR_API_TOKEN`, `TRACCAR_INGEST_TOKEN`(환경변수 또는 `.env.deploy`)이 있는지 확인하고 없으면 이미지를 올리기 전에 멈춘다(없는 채로 올리면 부팅하지 못하는 컨테이너가 만들어진다). 그 밖의 명령(`rollback` 등)은 그대로 `bin/kamal`에 넘긴다.

- 컨테이너가 부팅할 때 `bin/docker-entrypoint`가 `db:prepare`를 실행한다. 빈 DB면 스키마를 만들고, **운영에서는 시드를 실행하지 않는다**(`db/seeds.rb`는 비어 있고 데모 데이터는 `demo:seed`가 만들며 운영에서 `abort`한다). 데모 시드는 데모 계정(`operator@example.com`/`password123`)과 정류장·노선·차량을 만들고 Traccar에도 만들기 때문이다.
- 부팅할 때 `TraccarProductionCheck`가 Traccar 설정을 검사한다. 값이 없거나 개발용이면 `운영 Traccar 설정 오류: ...`로 부팅이 실패한다. 로그(`bin/kamal app logs`)에서 이유를 확인한다. 자세한 것은 아래 "부팅 검사".

### 부팅 검사: 운영 Traccar 설정 (`lib/traccar_production_check.rb`)

**무엇을 하나.** 운영 모드로 부팅할 때(`config/initializers/traccar_production_check.rb`) `TraccarProductionCheck.problems`가 Traccar 설정 네 가지(`TRACCAR_API_BASE_URL`, `TRACCAR_API_TOKEN`, `TRACCAR_INGEST_TOKEN`, `TRACCAR_SERVER_URL`)를 본다. 환경변수가 우선이고 없으면 credentials를 본다. 문제가 있으면 `운영 Traccar 설정 오류: <항목 목록>`으로 부팅을 막는다. 거부하는 것은 다음이다.
- 비었거나 공백뿐인 값(`api_token 없음`처럼 이름을 알려 준다)
- `dev-`로 시작하는 토큰(`api_token가 개발용 값(dev-...)`). 로컬 데모 토큰 `dev-traccar-*`는 공개 저장소에 있다.
- 개발 서버 주소: URL에 `iptime.org`, `localhost`, `127.0.0.1`이 들어 있는 경우(대소문자 무시, `api_base_url가 개발 서버를 가리킴(<주소>)`)

**왜 필요한가.** 이 검사가 없으면 값을 빠뜨린 배포가 **정상처럼 떠서** 나중에 따로따로 깨진다(모두 코드로 확인함).
- `TRACCAR_INGEST_TOKEN`이 비면 이벤트 수신(`traccar_events_controller.rb`)이 모든 요청을 401로 거절한다. 앱은 `/up` 200으로 멀쩡해 보이는데 Traccar만 재시도를 계속하고 도착 정보가 조용히 비게 된다.
- `TRACCAR_SERVER_URL`이 비면 앱 등록 응답이 `traccarServerUrl: null`이 되고, 운전자 앱이 `body['traccarServerUrl'] as String`에서 예외를 내 기사 등록이 실패한다.
- `TRACCAR_API_BASE_URL`이 비면 정류장·노선·차량 등록이 "Traccar API credentials가 설정되지 않았습니다"로 실패한다.
- 로컬 데모의 개발 토큰을 운영에 붙여 넣으면 누구나 이벤트를 위조할 수 있다. 이 검사만 이를 막는다.

검사가 있으면 이 모두가 **배포 때 컨테이너가 뜨지 않는 것**으로 바뀐다. kamal-proxy가 헬스체크를 통과하지 못한 대상을 거부하는 것(`target failed to become healthy`)은 로컬에서 확인했다. 첫 배포는 그 자리에서 실패로 끝나서 반쯤 동작하는 앱이 남지 않는다. 이전 배포가 있을 때 그 버전이 계속 서비스되는지는 확인하지 못했다.

**건너뛰는 경우.** `SECRET_KEY_BASE_DUMMY`가 있을 때(이미지 빌드의 `assets:precompile`), 그리고 개발·테스트 모드.

**부수 효과.** 운영 모드로 실행하는 모든 명령이 같은 검사를 받는다. 컨테이너 부팅 때의 `db:prepare`, `bin/kamal app exec`, `bin/rails runner`가 값이 비면 실패한다. 로컬에서 운영 모드를 시험할 때는 `SECRET_KEY_BASE_DUMMY=1`을 주거나 네 값을 준다. 이 PC에 `config/master.key`가 있으면 옛 `credentials.yml.enc`의 개발 서버 주소(`api_base_url`)를 읽어 걸린다.

**다른 안전장치와의 관계.** 셋이 서로 다른 곳을 막는다.
| 장치 | 보는 것 | 못 보는 것 |
|---|---|---|
| `bin/deploy` 사전 점검 | `production.key`, 토큰 두 개가 환경변수나 `.env.deploy`에 있는지 | `dev-` 값, 두 URL. `bin/kamal`을 직접 쓰면 거치지 않음 |
| `test/lib/traccar_production_check_test.rb` | `deploy.yml`이 네 설정을 내려 주고 그 값이 검사를 통과하는지, `.kamal/secrets`에 비밀 이름이 있는지, 부팅 | 배포하는 사람의 셸에서 오는 토큰 값. CI에는 테스트 잡이 없어 로컬에서 돌려야 함 |
| 이 부팅 검사 | 실제로 컨테이너가 받은 최종 값 | 아래 한계 |

**알려진 한계(모두 직접 확인함).** 이 검사는 값의 *모양*만 본다.
- **오탐**: 호스트 이름이 아니라 URL 문자열 전체에서 찾는다. `https://localhost-bus.codefor.kr`처럼 이름 일부이거나 `?from=iptime.org`처럼 경로에 들어 있어도 "개발 서버"로 거부한다. 지금 쓰는 주소(`where-is-my-bus.codefor.kr`, `where-is-my-bus-traccar`, `traccar.where-is-my-bus.codefor.kr`)에는 해당 없다.
- **놓치는 것**: 오타 난 호스트(`where-is-my-bus-traccr`), URL이 아닌 값(`not a url`), 스킴 없는 주소(`where-is-my-bus.codefor.kr:5055`), 대문자 `DEV-`, 서로 같은 두 토큰, 너무 짧은 토큰은 모두 통과한다. 연결이 되는지와 Traccar 쪽 토큰과 같은지는 보지 못하므로 **첫 배포 후 확인**(`docs/traccar-accessory.md`)으로 확인한다.
- `iptime.org`는 옛 `credentials.yml.enc`가 이미지에 들어가던 시절의 대비다. 지금은 `.dockerignore`가 그 파일을 막고 운영은 `production.yml.enc`를 쓰므로 주된 용도가 아니다.
- **HTTPS 전환 때**: 지금은 평문 `http://` 위치 수신 주소를 통과시킨다(임시, 테스트 "운영 주소는 거부하지 않는다"에 그렇게 적혀 있다). 전환 뒤에는 `http://` 위치 수신 주소를 거부하도록 규칙을 추가하고 그 테스트에서 평문 항목을 뺀다(`docs/future-improvements.md` 32번).

### 첫 가입자가 운영자다
**배포 직후 가장 먼저 본인이 `https://where-is-my-bus.codefor.kr/registration/new`에서 가입한다.** 첫 가입자가 자동으로 operator가 되고, 가입 폼은 공개되어 있다(`docs/future-improvements.md` 12번). 누가 언제 하는지 미리 정해 둔다. 가입 폼을 닫는 일은 후속 과제다.

### 확인
- `https://where-is-my-bus.codefor.kr/up`이 200이고 인증서가 유효하다.
- 관리자 화면에서 정류장 1개를 등록한다 → Traccar에 Geofence가 생긴다(Traccar 웹 UI에서 확인).
- 차량을 등록하고 운전자 앱으로 PIN 등록·운행을 시작한다. 위치를 보내면 Traccar 이벤트가 도착해 `stop_visits`가 생긴다.
- GA4(`G-V5FQ7DHE99`) 실시간 보고서에 `page_path`와 `arrival_status`가 보인다.

## 운영 정보 인수인계

운영을 넘겨받는 사람(운영자, 배포 담당)에게 **무엇을 어디로 전달하는지** 정리한다. 이 절에는 값을 적지 않는다. 저장소가 공개라 비밀번호·토큰·해시를 문서나 PR에 쓰면 안 된다. 값은 비밀번호 관리자의 공유 항목처럼 **저장소 밖**에서 전달한다(채팅·메일 본문에 평문으로 보내지 않는다).

### 전달할 항목 (양식)

| 항목 | 값 | 받는 사람 |
|---|---|---|
| 관리자 화면 주소 | `https://where-is-my-bus.codefor.kr/admin` | 운영자 |
| 관리자 로그인 | 이메일 주소 / 비밀번호 (첫 가입자 = operator, 위 "첫 가입자가 운영자다") | 운영자 |
| 위치 수신 주소 | `https://traccar.where-is-my-bus.codefor.kr` (`TRACCAR_SERVER_URL`) | 운영자·운전자(앱이 등록 때 자동으로 받는다) |
| Traccar 관리 화면 | `https://admin.traccar.where-is-my-bus.codefor.kr` | Traccar를 직접 볼 사람 |
| ㄴ 브라우저 인증 | 아이디 / 비밀번호 (`TRACCAR_ADMIN_HTPASSWD`의 계정) | 위와 같음 |
| ㄴ Traccar 로그인 | 이메일 주소 / 비밀번호 (`traccar:create_admin`으로 생성, 아래 "Traccar 관리자 계정 만들기") | 위와 같음 |
| `TRACCAR_API_TOKEN`, `TRACCAR_INGEST_TOKEN` | 배포 PC의 환경변수 또는 `.env.deploy` | **배포 담당만** |
| `production.key`, 레지스트리 토큰, 서버 SSH | 위 "배포 전 준비" | **배포 담당만** |

Traccar 관리 화면은 **두 단계**다. 먼저 브라우저 인증 창에서 아이디/비밀번호를 넣고, 통과하면 Traccar 로그인 화면에서 이메일 주소/비밀번호로 로그인한다. 인수인계 때 이 순서대로 접속되는지 받는 사람과 한 번 같이 확인한다.

### 운전자 앱에는 토큰이 필요 없다

`TRACCAR_API_TOKEN`과 `TRACCAR_INGEST_TOKEN`은 **서버끼리**(Rails ↔ Traccar) 쓰는 값이다. 운전자 앱에 입력하거나 운전자에게 알려 주지 않는다. 운전자 앱에 필요한 것은 두 가지뿐이다.

1. **서버 주소**: `https://where-is-my-bus.codefor.kr` (앱 등록 화면에 입력)
2. **차량 PIN**: 관리자 화면의 차량 상세. 1회용이고 쓰이면 소모된다.

등록하면 앱이 위치 수신 주소(`TRACCAR_SERVER_URL`)와 기기 ID를 서버에서 받아 간다(`driver_app/ISSUE.md`). 토큰이 앱 쪽에 새면 이벤트 위조나 Traccar 제어가 가능해지므로 앱 설정 안내에 토큰이 들어 있다면 빼야 한다.

### Traccar 관리자 계정 만들기

Traccar 관리 화면에 사람이 로그인할 계정은 서버의 Rails 컨테이너에서 만든다. 컨테이너에 이미 `TRACCAR_API_BASE_URL`·`TRACCAR_API_TOKEN`이 있어 **서비스 토큰으로 `POST /api/users`**를 부르고 `administrator: true`로 만든다(`app/services/traccar_admin_user.rb`, `lib/tasks/traccar.rake`).

```bash
# 비밀번호는 인자로 받지 않는다(셸 기록·ps에 남는다). TTY에서 실행하면 입력 프롬프트가 뜬다.
bin/kamal app exec --interactive --reuse "env TRACCAR_ADMIN_EMAIL=<이메일> bin/rails traccar:create_admin"
```

- **이미 있는 이메일은 건드리지 않는다**(비밀번호를 덮어쓰지 않고 "이미 있는 계정입니다"로 끝난다). 여러 번 실행해도 안전하다. 비밀번호를 잊었으면 Traccar 관리 화면의 사용자 편집에서 바꾼다.
- `TRACCAR_ADMIN_PASSWORD` 환경변수로 줄 수도 있지만 명령줄에 남으므로 프롬프트를 권한다. 값은 저장소·PR에 쓰지 않는다.
- 이 계정은 Rails 동작과 무관하다. 관리 화면에 들어갈 사람 수만큼만 만든다.
- **로컬 Traccar에서 확인한 것**: 서비스 토큰으로 계정이 만들어지고, 그 계정이 관리자이며(`/api/users` 목록 조회 200, 틀린 비밀번호 401), 같은 이메일 재실행은 건너뛴다. **확인하지 못한 것**: `WEB_REGISTRATION=false`인 운영 Traccar에서의 동작(로컬 `bin/traccar`는 가입을 막지 않는다). 관리자가 서비스 토큰으로 사용자를 만드는 경로는 가입 허용 여부와 무관할 것으로 보지만, 첫 실행 때 응답(`403` 등)을 확인한다. 막히면 Traccar를 잠깐 `WEB_REGISTRATION=true`로 올려 첫 계정을 만들고 되돌리는 방법이 있으나, 그동안 누구나 가입할 수 있으므로 권하지 않는다.

### 인수인계 확인 목록

- [ ] 관리자 이메일/비밀번호로 `/admin` 로그인
- [ ] Traccar 관리 화면: 브라우저 인증 → Traccar 로그인 순서로 접속
- [ ] 비밀번호 관리자에 위 값들이 보관돼 있다(배포 PC를 바꿔도 복구 가능)
- [ ] 배포 담당이 `bin/deploy`를 실행할 수 있다(`gh` 로그인, `.env.deploy`, `production.key`)
- [ ] 운전자에게는 서버 주소와 PIN만 전달했다
- [ ] 임시 평문 5055·8082 게시와 보안 그룹 규칙이 남아 있다면 담당자와 정리 시점을 정했다("첫 배포의 위치 수신은 임시로 평문(HTTP)이다")

## 빌드가 멈출 때 (첫 배포에서 겪은 것, 2026-11-01)

`bin/deploy setup`이 `#22 pushing manifest … done`과 `DONE`까지 찍은 뒤 아무 반응이 없었다.

- **확인한 것**: GHCR에는 `latest`와 커밋 태그가 올라가 있었고(push 성공), 서버에는 컨테이너·이미지가 하나도 없었다(Kamal이 서버 pull 단계에 못 갔다). 로컬의 `docker buildx build` 프로세스는 CPU 0%로 살아 있었고 buildkit은 유휴였다. 다시 실행해도 같은 지점에서 멈췄고, Docker Desktop에는 완료되지 않은 빌드가 2개 남았다.
- **원인은 확정하지 못했다.** buildx가 push 뒤 종료하지 못하는 것으로 보인다. buildx는 기본으로 출처·SBOM 증명(attestation)을 붙이며 buildkit 로그에 `forcibly turning on oci-mediatype mode for attestations`가 찍혔고, GHCR에는 이미지 외에 **이름 없는 버전**이 2개 더 올라갔다. 그래서 `deploy.yml`의 `builder`에 `provenance: false`, `sbom: false`를 넣었다(Kamal이 `--provenance false --sbom false`를 넘기는 것을 확인했다). 이 설정으로 멈춤이 사라지는지는 아직 확인하지 못했다.
- **멈췄을 때**: `Ctrl+C`로 중단하고, Docker Desktop의 Builds 화면에서 남은 활성 빌드를 정리하거나 `docker buildx stop kamal-local-docker-container`로 빌더를 멈춘 뒤 다시 `bin/deploy setup`을 실행한다. 이미지가 레지스트리에 있어 빌드 캐시로 빨리 지나간다. 배포 잠금 오류가 나면 `bin/kamal lock release`.
- 서버에는 `.kamal/lock-where-is-my-bus` 디렉터리만 남는다. `Ctrl+C`가 서버를 바꾸지는 않는다.

## 이미지 크기와 레지스트리 무료 한도

운영 이미지(arm64, `Dockerfile` 기준)를 실제로 빌드해 쟀다(2026-11-01). `image_processing` gem과 `libvips`를 뺀 뒤의 값이다.

| 항목 | 크기 |
|---|---|
| 로컬 이미지(압축 전) | 약 501 MB (제거 전 약 609 MB) |
| **레지스트리에 저장되는 크기**(레이어를 gzip으로 압축한 추정) | **약 185 MB** (제거 전 약 219 MB) |
| 코드만 바꾼 다음 배포가 새로 쌓는 양(마지막 `/rails` 레이어만 바뀜) | 약 26 MB |
| `Gemfile.lock`이 바뀐 배포가 새로 쌓는 양 | 위 26 MB + gem 레이어(제거 전 약 78 MB) |

- 레이어별 압축 크기는 제거 전에 쟀다(MB): 기반 Debian 29, Ruby 47, `apt` 패키지 39, gem 78, 앱 26. 제거 후에는 합계만 다시 쟀다. 레지스트리가 실제로 계산하는 값은 재지 못했다(위는 `gzip -6` 추정이라 오차가 있다).
- **GitHub 비공개 패키지 무료 한도(GitHub Free: 저장 500MB, 전송 월 1GB)와 비교**: 첫 push 약 185MB는 저장 한도의 37%다. 모든 버전을 남기면 코드만 바꾼 배포 약 12회에서 500MB에 닿는다(`(500−185)/26`). 전송은 서버가 첫 pull 약 185MB + 배포마다 약 26MB를 받으므로 월 1GB로 배포 약 30회다. **단 이 한도는 비공개 패키지에만 해당한다.** 공개 패키지는 무료이고 컨테이너 레지스트리의 저장·대역폭은 문서상 "현재 무료"다(변경 시 최소 1개월 전 공지). 한도가 *압축 크기*로 계산되는지는 문서에서 확인하지 못했다. 압축 전 크기(501MB)로 센다면 한도(500MB)에 딱 닿는다.
- Kamal은 레지스트리의 옛 버전을 지우지 않는다. 오래된 태그 정리는 따로 해야 한다(GitHub 패키지 화면).
- **`image_processing` gem과 `libvips`는 제거했다.** 앱은 첨부 파일과 이미지 변환을 쓰지 않는다(`has_one_attached`, `variant`, Active Storage 테이블 모두 없음). `Gemfile`, `Gemfile.lock`(`image_processing`, `mini_magick`, `ruby-vips`, `ruby-vips`만 쓰던 `ffi`), `Dockerfile`·`Dockerfile.dev`에서 뺐고, 빼면 부팅 때 나오는 경고를 `config.active_storage.variant_processor = :disabled`로 껐다. 이미지가 부팅해 `/up`과 주요 경로가 200이고 경고가 없다. 이미지 변환을 쓰게 되면 gem을 다시 넣고 이 줄을 지운다.
- **나중에 이미지 변환(첨부 이미지의 크기 조절 등)이 필요해지면 gem과 라이브러리를 다시 추가해야 한다.** gem만 또는 `libvips`만 되살리면 부팅 때 경고가 난다(`libvips`만 빼고 gem을 두면 `Using vips to process variants requires the libvips library`, gem만 빼고 설정이 없으면 `Generating image variants require the image_processing gem`). 절차(모두 시험하지는 않았다):
  1. `Gemfile`에 `gem "image_processing", "~> 1.2"`를 넣고 `bundle install`.
  2. `Dockerfile`의 런타임 `apt-get install` 줄과 빌드 단계 줄, `Dockerfile.dev`에 `libvips`를 다시 넣는다. (이 변경을 되돌리는 것과 같다. 압축 저장 크기가 약 33MB 늘어난다: 약 185MB → 약 219MB, 위 측정.)
  3. `config/application.rb`의 `config.active_storage.variant_processor = :disabled`와 주석을 지운다.
  4. Active Storage 테이블이 아직 없으므로 `bin/rails active_storage:install` 후 `bin/rails db:migrate`(시험하지 못함). 업로드 파일은 `config.active_storage.service = :local`이라 컨테이너 안 `storage/`, 곧 호스트 `/var/lib/where-is-my-bus/storage`에 쌓이고 배포로 사라지지 않으며 `bin/backup-storage`가 `files.tar.gz`로 백업한다.
  5. 이미지를 다시 빌드해 부팅 경고가 없는지 보고, 크기와 메모리(이미지 변환은 메모리를 더 쓸 수 있다, 재지 않았다)를 `t4g.micro`에서 확인한다.
- Active Storage 엔진 자체는 아직 로드된다(`config/application.rb`의 `require "active_storage/engine"`, 환경별 `config.active_storage.service`). 쓰지 않으므로 걷어낼 수 있다(`future-improvements.md` 31번).
- **로컬에서 `/`로 요청하면 403이 나온다.** 운영 모드는 `config.hosts`가 `where-is-my-bus.codefor.kr`와 `rails-app`만 허용하기 때문이다(`Host`를 도메인으로 주면 200). 로컬 컨테이너 시험에서는 `curl -H 'Host: where-is-my-bus.codefor.kr' ...`로 한다.

## 이후 배포·롤백

```bash
bin/deploy                        # 새 버전 배포(무중단 교체). = bin/deploy deploy
bin/deploy rollback <이전 버전>     # bin/kamal app containers 로 버전 확인
bin/kamal app exec --interactive --reuse "bin/rails console"
```

교체하는 동안 새·옛 컨테이너가 같은 SQLite 파일을 잠깐 함께 쓴다(Rails 8 기본 구성과 같은 수준).

## 데이터와 백업

데이터는 컨테이너 밖 `/var/lib/where-is-my-bus/storage`에 있어 컨테이너를 지우거나 이미지를 바꿔도 남는다.

실행 중인 SQLite 파일을 `cp`하면 쓰는 도중에 복사돼 깨질 수 있다. **서버에서 `bin/backup-storage`를 쓴다.** `sqlite3 .backup`으로 일관된 스냅샷을 만들고 무결성 검사 후 gzip한다. SQLite 외 파일(Active Storage)은 `files.tar.gz`로 묶는다.

```bash
# 서버에서 (이 저장소의 bin/backup-storage를 서버로 복사해 둔다)
STORAGE_DIR=/var/lib/where-is-my-bus/storage BACKUP_DIR=/var/backups/where-is-my-bus KEEP_DAYS=14 ./backup-storage

# cron 예: 매일 03:10
10 3 * * *  /opt/where-is-my-bus/backup-storage >> /var/log/where-is-my-bus-backup.log 2>&1
```

- 같은 디스크의 백업만으로는 디스크 장애에 대비하지 못한다. `rclone`·`rsync`로 **다른 서버나 오브젝트 스토리지에 사본을 하나 더** 둔다.
- 데이터가 쌓이기 전에 **복원 리허설을 한 번** 한다:

```bash
d=/var/backups/where-is-my-bus/<백업 시각>
mkdir /tmp/restore && gunzip -c $d/production.sqlite3.gz > /tmp/restore/production.sqlite3
sqlite3 /tmp/restore/production.sqlite3 "select count(*) from users;"
```

- 실제 복원: 컨테이너를 멈추고(`bin/kamal app stop`) 호스트 `storage/`의 해당 파일을 백업본으로 바꾼 뒤 `chown 1000:1000`, `bin/kamal app boot`.
- **Traccar DB(H2, `/var/lib/where-is-my-bus/traccar`)도 이 서버에 있다.** 실행 중인 H2 파일을 `cp`하면 깨질 수 있어 Traccar를 잠깐 멈추고 복사한다([traccar-accessory.md](traccar-accessory.md) "데이터와 백업"). Rails만 복원하면 Traccar와 ID가 어긋나므로 **같은 시각에 함께 백업·복원한다**(`docs/future-improvements.md` 19번).

## 운영 데이터 초기화와 초기 데이터 입력 (제안)

> **제안이며 실제 서버에서 실행해 보지 않았다.** 운영에는 시드가 없으므로(`demo:seed`는 운영에서 `abort`) 처음 채우는 일과 시험 데이터를 지우는 일은 모두 이 절을 따른다. 데이터를 지우는 작업이라 **실행 전에 백업을 먼저 하고, 무엇을 지우는지 확인한 뒤 사람이 직접 실행한다.**

### 먼저 무엇을 지울지 고른다

| 목적 | 지우는 것 | Traccar | 쓰는 때 |
|---|---|---|---|
| **A. 운행 기록만** | `stop_visits`, `trips` | 그대로 | 시험 운행 기록을 비우고 노선·정류장·차량은 유지 |
| **B. 전체 초기화** | Rails DB 4개 + Traccar DB | 함께 지움 | 시험 데이터를 모두 버리고 처음부터 다시 입력 |
| ~~Rails만 지움~~ | Rails DB만 | 남음 | **하지 않는다.** Traccar에 Geofence·그룹·기기가 남아 ID가 어긋난다(`future-improvements.md` 19번) |

Rails DB와 Traccar DB는 **같은 시각에 함께** 다룬다. A는 Traccar를 건드리지 않아 위험이 적고, B는 되돌릴 수 없다.

### 공통: 백업

```bash
# 서버에서. Rails(SQLite 4개)와 Traccar(H2)를 같은 시각에 받는다.
./backup-storage                      # 위 "데이터와 백업"
bin/kamal accessory stop traccar      # H2는 멈춘 뒤에 복사한다
sudo cp -a /var/lib/where-is-my-bus/traccar /var/backups/where-is-my-bus/traccar-$(date +%Y%m%d-%H%M%S)
bin/kamal accessory boot traccar      # A만 할 거라면 다시 올린다
```

백업이 실제로 열리는지(`sqlite3 ... "select count(*) from users;"`)까지 본 뒤에 다음으로 간다.

### A. 운행 기록만 지우기

운행 중인 버스가 없을 때 한다. 운행이 열려 있으면(`ended_at` nil) 먼저 종료한다.

```bash
bin/kamal app exec --interactive --reuse "bin/rails runner 'p Trip.where(ended_at: nil).count'"   # 0이어야 한다
bin/kamal app exec --interactive --reuse "bin/rails runner 'StopVisit.delete_all; Trip.delete_all; puts :done'"
```

노선·정류장·차량·PIN은 그대로라 운전자 앱을 다시 등록할 필요가 없다. Traccar의 이벤트 ID는 계속 이어지므로 중복 방지 키(이벤트 ID와 시각을 합친 키) 충돌도 없다.

### B. 전체 초기화

```bash
bin/kamal app stop                    # Rails 정지(이벤트 수신 중단)
bin/kamal accessory stop traccar
# 지우지 말고 옮긴다. 확인 후에 지운다.
sudo mkdir -p /var/backups/where-is-my-bus/reset-$(date +%Y%m%d)
sudo mv /var/lib/where-is-my-bus/storage/*.sqlite3* /var/backups/where-is-my-bus/reset-$(date +%Y%m%d)/
sudo mv /var/lib/where-is-my-bus/traccar/* /var/backups/where-is-my-bus/reset-$(date +%Y%m%d)/
bin/kamal accessory boot traccar      # 빈 H2로 시작. 서비스 토큰은 환경변수라 계정을 따로 만들 필요가 없다
bin/kamal app boot                    # db:prepare가 빈 DB 4개를 만든다(시드 없음)
```

- 경로를 눈으로 확인한 뒤 실행한다. `storage/` 안의 `*.sqlite3*`만 옮기고 디렉터리 자체와 소유자(`1000:1000`)는 그대로 둔다.
- 끝나면 `https://<도메인>/up`이 200이고 `users`가 0이어야 한다. **운전자 폰의 등록 정보는 무효가 된다**(차량·PIN이 새로 생기므로). 모든 기기가 다시 등록해야 한다.
- 이 상태에서는 **첫 가입자가 자동 operator**다. 아래 순서의 1번을 바로 이어서 한다.

### 초기 데이터 입력 순서

관리자 화면(`/admin`)에서 입력한다. 정류장·노선·차량 등록은 Traccar 호출과 한 트랜잭션이라, 입력하는 순간 Traccar에 Geofence·그룹·기기가 만들어진다.

1. **운영자 가입**: `/registration/new`에서 가장 먼저 가입한다(첫 가입자가 operator).
2. **정류장**: 이름과 좌표(`lat`, `lng`)를 입력한다 → Geofence 생성. 좌표는 입력 전에 표로 정리해 둔다.
3. **노선**: 이름을 입력한다 → Traccar 그룹 생성. 이름은 중복되면 안 된다.
4. **노선에 정류장 연결**: 노선 상세에서 정차 순서대로 추가한다(순서는 나중에 바꾸기 어렵다, `future-improvements.md` 11번).
5. **차량**: 번호판(필수, 중복 불가)을 입력하고 **노선을 배정한다**. PIN(6자리)과 `traccar_unique_id`가 자동 생성된다.
6. **PIN 전달**: 차량 상세의 PIN과 서버 주소를 운전자에게 전달한다. PIN은 1회용이라 쓰이면 소모되고, 분실·기기 교체는 "PIN 재발급".
7. **확인**: Traccar 웹 UI에서 Geofence·그룹·기기 개수가 Rails의 정류장·노선·차량 수와 같은지, 승객 화면에 노선·정류장이 보이는지 본다. 어긋나면 admin의 `sync_geofence`·`sync_group`·`sync_device`로 다시 맞춘다.

입력할 값을 미리 표로 만들어 두면 실수가 준다:

| 항목 | 필요한 값 |
|---|---|
| 정류장 | 이름, 위도, 경도 |
| 노선 | 이름, 정류장 순서 목록 |
| 차량 | 번호판, 차량 번호(선택), 배정 노선 |

### 자동화가 필요해지면 (후속 제안)

지금 규모(정류장 몇 개, 노선 몇 개)는 위 수동 입력이 가장 안전하다. 규모가 늘거나 B를 자주 하게 되면 **CSV/YAML을 읽어 `*Registration` 서비스로 등록하는 rake 작업**(예: `ops:bootstrap`)을 만든다.
- `Stop.create` 같은 직접 생성이 아니라 `StopRegistration` 등을 통해야 Traccar 동기화와 롤백 규칙이 적용된다(`docs/traccar-integration.md`).
- 이미 있으면 건너뛰도록 멱등하게 만들고, `demo:seed`처럼 운영 가드는 두되 **명시적 확인 환경변수가 있을 때만** 실행한다.
- 파일에는 PIN·토큰을 넣지 않는다(저장소가 공개다).

## 마이그레이션

새 서버·빈 DB에서는 컨테이너 부팅 시 `db:prepare`가 4개 DB를 모두 만든다.

| DB | 마이그레이션 | 비고 |
|---|---|---|
| `production` | `create_users`, `create_sessions`, `create_domain_tables`, `add_route_to_buses` | 4개 모두 적용 |
| `production_cache`, `production_queue`, `production_cable` | 스키마 파일(`db/*_schema.rb`)로 생성 | 상태에 `001 NO FILE`로 보이는 것은 정상이다 |

- 마이그레이션 파일이 늘어나면 컨테이너가 새 버전으로 뜰 때 `db:prepare`가 자동으로 적용한다. 배포 전에 `bin/rails db:migrate:status`로 대기 중인 것을 확인한다.
- **재작성(#23) 이전 구조의 DB를 옮겨 오는 것은 지원하지 않는다.** 옛 테이블(`regions`, `areas`, `gps_logs` 등)이 있으면 `create_table`이 충돌한다. 운영은 빈 DB에서 시작한다.

## 도메인 변경

네 곳을 같이 바꾼다.

1. `config/deploy.yml`의 `proxy.host`
2. `config/environments/production.rb`의 `config.hosts`(같은 도메인 문자열). **빼먹으면 프록시는 통과시키는데 Rails가 403을 줘서 사이트 전체가 막힌다.** `bin/rails test test/lib/production_hosts_test.rb`가 두 값의 불일치를 잡는다(CI에는 테스트 잡이 없으니 로컬에서 돌린다)
3. 운영 credentials의 `site_url`
4. 운전자 앱이 받는 위치 전송 주소 `TRACCAR_SERVER_URL`(`deploy.yml` `env.clear`)

DNS의 A 레코드를 먼저 옮기고 배포한다.

## 로컬에서 확인한 것

- 이미지가 빌드된다(Ruby 4.0.9-slim, 에셋 프리컴파일 포함).
- 빈 스토리지 디렉터리를 마운트하고 `RAILS_ENV=production`으로 `db:prepare`를 실행하면 4개 DB가 만들어지고 `users=0`이며(시드 데이터 없음), 두 번 실행해도 오류가 없다.
- 이미지에 키 파일·`.env`·SQLite·`settings.local.json`·개발용 credentials·문서·테스트·에이전트 디렉터리가 들어 있지 않다.
- Traccar accessory와 같은 설정(환경변수, 네트워크 별칭 `rails-app`)으로 도커 네트워크에서 `geofenceEnter` 이벤트가 `Host: rails-app`, `X-Ingest-Token` 헤더와 함께 도착한다. 수신 쪽은 실제 Rails가 아니라 간이 수신기였다.
- 확인하지 못한 것: 서버 배포, Let's Encrypt 발급, 실제 Rails 컨테이너가 포워딩을 받는지, 호스트 디렉터리 권한, 실기기 운행.
