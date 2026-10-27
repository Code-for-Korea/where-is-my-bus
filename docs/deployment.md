# 운영 배포 (Kamal)

Rails 앱만 Kamal로 서버에 올린다. Traccar는 이미 설치된 별도 서버(`testtraccar.codefor.kr`)를 쓰며 Kamal accessory로 올리지 않는다.
도메인은 `localbus.codefor.kr`(나중에 바꿀 수 있다 — "도메인 변경").

> 이 문서는 **아직 실제 서버에서 끝까지 실행해 보지 않았다.** 이미지 빌드, 빈 DB에서의 `db:prepare`, 이미지 내용 검사는 로컬에서 확인했고(아래 "로컬에서 확인한 것"), 서버 배포·인증서 발급·Traccar 연동은 첫 배포 때 확인한다.

## 구성

```
운전자 앱 ──위치──▶ Traccar(testtraccar.codefor.kr) ──Geofence 이벤트──▶ https://localbus.codefor.kr/integrations/traccar/events
                         ▲                                                     │ (X-Ingest-Token)
                         └──── Rails가 Traccar API 호출(서비스 토큰) ◀──────────┘
승객 ──▶ https://localbus.codefor.kr  (kamal-proxy가 HTTPS 종단 → 컨테이너 80 → Thruster → Puma)
```

| 항목 | 값 | 위치 |
|---|---|---|
| 이미지 | Docker Hub **공개** 저장소 `<계정>/where-is-my-bus` | `config/deploy.yml` `image`, `registry.username` |
| 서버 | Rails를 올릴 서버 1대 | `config/deploy.yml` `servers.web` |
| 데이터 | 호스트 `/var/lib/where-is-my-bus/storage` (컨테이너 밖) | `config/deploy.yml` `volumes` |
| 비밀값 | `config/credentials/production.yml.enc` (키: `production.key`) | Rails credentials |
| Traccar 접속 | credentials의 `traccar.*` (환경변수가 있으면 우선) | [traccar-integration.md](traccar-integration.md) |

`config/deploy.yml`의 `DOCKERHUB_USER`, `SERVER_IP`는 아직 자리표시자다. 배포 전에 실제 값으로 바꾼다.

## 배포 전 준비 (한 번만)

### 1. DNS·서버
- `localbus.codefor.kr`의 A 레코드를 Rails 서버 IP로 만든다. Let's Encrypt 발급이 이 레코드를 필요로 하므로 `dig +short localbus.codefor.kr`로 먼저 확인한다.
- 서버에 Docker를 설치하고, 배포하는 PC에서 SSH로 접속할 수 있어야 한다(배포 사용자가 `docker` 그룹). 방화벽에서 80/443을 연다.
- **Rails를 Traccar와 같은 호스트에 올린다면** 80/443을 이미 Traccar의 리버스 프록시가 쓰고 있을 수 있다. Kamal proxy가 같은 포트를 잡지 못하므로, 그 경우에는 기존 프록시에 `localbus.codefor.kr` 서버 블록을 추가하는 구성으로 바꿔야 한다. 서버가 정해지면 먼저 확인한다.

### 2. 호스트 데이터 디렉터리
SQLite 4개(`production`, `production_cache`, `production_queue`, `production_cable`)와 Active Storage 파일이 여기에 쌓인다. 컨테이너는 uid 1000(`rails`)으로 돌기 때문에 권한이 필요하다. **빼먹으면 `db:prepare`가 실패해 컨테이너가 뜨지 않는다.**

```bash
sudo mkdir -p /var/lib/where-is-my-bus/storage
sudo chown 1000:1000 /var/lib/where-is-my-bus/storage
sudo mkdir -p /var/backups/where-is-my-bus
sudo apt install -y sqlite3        # bin/backup-storage가 쓴다
```

### 3. Docker Hub
- 공개 저장소 `<계정>/where-is-my-bus`를 만든다. `deploy.yml`의 `DOCKERHUB_USER`를 그 계정으로 바꾼다.
- **Access Token**(Read & Write)을 만들어 배포하는 PC의 환경변수 `KAMAL_REGISTRY_PASSWORD`로 둔다. 계정 비밀번호를 쓰지 않는다. `.kamal/secrets`에는 값을 쓰지 않고 환경변수를 참조만 한다(이 파일은 git에 있다).

### 4. 운영 credentials 만들기
**`.gitignore`가 `/config/credentials/*.key`를 막는지 먼저 확인한 뒤** 만든다(막지 않으면 `git add -A`로 키가 커밋된다).

```bash
git check-ignore -v config/credentials/production.key   # 무시 규칙이 출력돼야 한다
bin/rails credentials:edit --environment production
```

편집기에 넣을 값:

```yaml
secret_key_base: <자동 생성된 값 그대로>
site_url: https://localbus.codefor.kr
traccar:
  api_base_url: https://testtraccar.codefor.kr
  api_token: <openssl rand -hex 32 로 새로 만든 값 — Traccar의 web.serviceAccountToken과 같아야 함>
  ingest_token: <openssl rand -hex 32 로 새로 만든 값 — Traccar의 event.forward.header 토큰과 같아야 함>
  server_url: <운전자 앱이 위치를 보낼 주소, 예: http://testtraccar.codefor.kr:5055>
```

- `config/credentials/production.key`를 **비밀번호 관리자 등에 백업**한다. 잃으면 `production.yml.enc`를 열 수 없다. git·이미지에는 들어가지 않는다(`.gitignore`, `.dockerignore`).
- 로컬 데모 토큰(`dev-traccar-*`)은 공개 저장소에 있으므로 **운영에서 쓰지 않는다.** 쓰거나 값이 비어 있으면 앱이 부팅하지 않는다(`TraccarProductionCheck`).
- `production.yml.enc`는 암호문이라 커밋해도 되고 이미지에도 들어간다. 저장소가 공개이므로 안전성은 `production.key`에 달려 있다. 키가 유출되면 `credentials:edit`로 키를 다시 만들고 토큰도 바꾼다.

### 5. 기존 Traccar 서버 설정 (서버 관리자)
`traccar.xml`에서 설정하고 Traccar를 재시작한다.

| 키 | 값 |
|---|---|
| `web.serviceAccountToken` | credentials의 `traccar.api_token`과 같은 값 |
| `event.forward.url` | `https://localbus.codefor.kr/integrations/traccar/events` |
| `event.forward.type` | `json` |
| `event.forward.header` | `X-Ingest-Token: <credentials의 traccar.ingest_token>` |
| `web.registration` | 끈다. 지금 `/api/server`가 `"registration": true`라 누구나 계정을 만들 수 있다 |

- 포워딩은 **Rails를 먼저 띄운 뒤** 설정한다(떠 있지 않은 동안은 포워딩이 실패한다).
- 이 Traccar에 다른 기기·그룹·지오펜스가 이미 있으면 Rails가 만드는 자원과 섞인다. Rails 전용으로 써도 되는지 확인한다.
- 운전자 앱이 위치를 보내는 5055 포트가 외부에서 열려 있는지 확인한다(`credentials`의 `server_url`).

## 이미지에 넣지 않는 것 (공개 이미지)

Docker Hub 공개 이미지는 누구나 받아서 내용을 볼 수 있고, 한 번 올린 것은 회수할 수 없다. `.dockerignore`가 아래를 막는다.

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

## 첫 배포

```bash
export KAMAL_REGISTRY_PASSWORD=<Docker Hub Access Token>
bin/kamal setup            # 서버 준비, 이미지 빌드·push, 컨테이너 기동, 인증서 발급
bin/kamal app logs         # 부팅 로그
```

- 컨테이너가 부팅할 때 `bin/docker-entrypoint`가 `db:prepare`를 실행한다. 빈 DB면 스키마를 만들고, **운영에서는 시드를 실행하지 않는다**(`db/seeds.rb`의 운영 가드). 시드는 데모 계정(`operator@example.com`/`password123`)과 정류장·노선·차량을 만들고 Traccar에도 만들기 때문이다.
- 부팅할 때 `TraccarProductionCheck`가 Traccar 설정을 검사한다. 값이 없거나 개발용(`dev-` 토큰, `iptime.org`·`localhost` 주소)이면 `운영 Traccar 설정 오류: ...`로 부팅이 실패한다. 로그에서 이유를 확인한다.

### 첫 가입자가 운영자다
**배포 직후 가장 먼저 본인이 `https://localbus.codefor.kr/registration/new`에서 가입한다.** 첫 가입자가 자동으로 operator가 되고, 가입 폼은 공개되어 있다(`docs/future-improvements.md` 12번). 누가 언제 하는지 미리 정해 둔다. 가입 폼을 닫는 일은 후속 과제다.

### 확인
- `https://localbus.codefor.kr/up`이 200이고 인증서가 유효하다.
- 관리자 화면에서 정류장 1개를 등록한다 → Traccar에 Geofence가 생긴다(Traccar 웹 UI에서 확인).
- 차량을 등록하고 운전자 앱으로 PIN 등록·운행을 시작한다. 위치를 보내면 Traccar 이벤트가 도착해 `stop_visits`가 생긴다.
- GA4(`G-V5FQ7DHE99`) 실시간 보고서에 `page_path`와 `arrival_status`가 보인다.

## 이후 배포·롤백

```bash
bin/kamal deploy                  # 새 버전 배포(무중단 교체)
bin/kamal rollback <이전 버전>      # bin/kamal app containers 로 버전 확인
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
- Traccar 쪽 DB(H2)는 그 서버 관리자의 백업 범위다. Rails만 복원하면 Traccar와 ID가 어긋날 수 있다(`docs/future-improvements.md` 19번).

## 마이그레이션

새 서버·빈 DB에서는 컨테이너 부팅 시 `db:prepare`가 4개 DB를 모두 만든다.

| DB | 마이그레이션 | 비고 |
|---|---|---|
| `production` | `create_users`, `create_sessions`, `create_domain_tables`, `add_route_to_buses` | 4개 모두 적용 |
| `production_cache`, `production_queue`, `production_cable` | 스키마 파일(`db/*_schema.rb`)로 생성 | 상태에 `001 NO FILE`로 보이는 것은 정상이다 |

- 마이그레이션 파일이 늘어나면 컨테이너가 새 버전으로 뜰 때 `db:prepare`가 자동으로 적용한다. 배포 전에 `bin/rails db:migrate:status`로 대기 중인 것을 확인한다.
- **재작성(#23) 이전 구조의 DB를 옮겨 오는 것은 지원하지 않는다.** 옛 테이블(`regions`, `areas`, `gps_logs` 등)이 있으면 `create_table`이 충돌한다. 운영은 빈 DB에서 시작한다.

## 도메인 변경

세 곳을 같이 바꾼다.

1. `config/deploy.yml`의 `proxy.host`와 `env.clear.APP_HOST`
2. 운영 credentials의 `site_url`
3. Traccar `traccar.xml`의 `event.forward.url`

DNS의 A 레코드를 먼저 옮기고 배포한다.

## 로컬에서 확인한 것

- 이미지가 빌드된다(Ruby 4.0.9-slim, 에셋 프리컴파일 포함).
- 빈 스토리지 디렉터리를 마운트하고 `RAILS_ENV=production`으로 `db:prepare`를 실행하면 4개 DB가 만들어지고 시드는 실행되지 않으며(`users=0`), 두 번 실행해도 오류가 없다.
- 이미지에 키 파일·`.env`·SQLite·`settings.local.json`·개발용 credentials·문서·테스트·에이전트 디렉터리가 들어 있지 않다.
- 확인하지 못한 것: 서버 배포, Let's Encrypt 발급, Traccar 포워딩, 호스트 디렉터리 권한, 실기기 운행.
