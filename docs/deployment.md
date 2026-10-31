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
| 이미지 | Docker Hub **공개** 저장소 `<계정>/where-is-my-bus` | `config/deploy.yml` `image`, `registry.username` |
| 서버 | Rails를 올릴 서버 1대 | `config/deploy.yml` `servers.web` |
| 데이터 | 호스트 `/var/lib/where-is-my-bus/storage` (컨테이너 밖) | `config/deploy.yml` `volumes` |
| 비밀값 | `config/credentials/production.yml.enc` (키: `production.key`) | Rails credentials |
| Traccar | 같은 서버의 accessory. 토큰은 배포 PC의 환경변수 `TRACCAR_API_TOKEN`, `TRACCAR_INGEST_TOKEN` | `config/deploy.yml` `accessories`, `.kamal/secrets` |
| Traccar 접속 설정 | 환경변수가 credentials보다 우선 | [traccar-integration.md](traccar-integration.md) |

`config/deploy.yml`의 `DOCKERHUB_USER`, `SERVER_IP`는 아직 자리표시자다. 배포 전에 실제 값으로 바꾼다.

## 배포 전 준비 (한 번만)

### 1. DNS·서버
- `where-is-my-bus.codefor.kr`의 A 레코드를 Rails 서버 IP로 만든다. Let's Encrypt 발급이 이 레코드를 필요로 하므로 `dig +short where-is-my-bus.codefor.kr`로 먼저 확인한다.
- 서버를 AWS에 만들거나 껐다 켜면 IP가 바뀌는 문제는 [aws-server-operations.md](aws-server-operations.md)를 본다(Elastic IP 권장).
- 서버에 Docker를 설치하고, 배포하는 PC에서 SSH로 접속할 수 있어야 한다(배포 사용자가 `docker` 그룹). 방화벽에서 80/443을 연다.
- 방화벽(보안 그룹)에서 **5055**(운전자 앱의 위치 전송)도 연다. Traccar 웹(8082)은 열지 않는다. 서버를 새로 만들고 Traccar는 이 서버에서만 돈다. 80/443을 쓰는 다른 프록시가 없는 서버여야 한다.
- `deploy.yml`의 `servers.web.hosts`와 `accessories.traccar.host`에 같은 서버를 적는다.

### 2. 호스트 데이터 디렉터리
`storage/`에는 SQLite 4개(`production`, `production_cache`, `production_queue`, `production_cable`)와 Active Storage 파일이, `traccar/`에는 Traccar의 H2 DB가 쌓인다. 컨테이너는 uid 1000(`rails`)으로 돌기 때문에 권한이 필요하다. **빼먹으면 `db:prepare`가 실패해 컨테이너가 뜨지 않는다.**

```bash
sudo mkdir -p /var/lib/where-is-my-bus/storage /var/lib/where-is-my-bus/traccar
sudo chown 1000:1000 /var/lib/where-is-my-bus/storage      # Rails(uid 1000). traccar 디렉터리는 컨테이너가 root라 불필요
sudo mkdir -p /var/backups/where-is-my-bus
sudo apt install -y sqlite3        # bin/backup-storage가 쓴다
```

### 3. Docker Hub
- 공개 저장소 `<계정>/where-is-my-bus`를 만든다. `deploy.yml`의 `DOCKERHUB_USER`를 그 계정으로 바꾼다.
- **Access Token**(Read & Write)을 만든다. 계정 비밀번호를 쓰지 않는다.
- 사용자 이름과 토큰은 **`bin/deploy`가 실행할 때 입력받는다**(토큰은 화면에 보이지 않는다). 환경변수 `KAMAL_REGISTRY_USERNAME`, `KAMAL_REGISTRY_PASSWORD`가 이미 있으면 묻지 않는다. 파일에는 값을 쓰지 않는다. `.kamal/secrets`는 환경변수를 참조만 한다(이 파일은 git에 있다).

#### 레지스트리를 GitHub 컨테이너 레지스트리(GHCR)로 쓰려면 (검토 결과, 아직 적용하지 않았다)

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
- 첫 가입 전에 **Traccar에 사람이 로그인할 일이 없다.** 웹(8082)이 서버 밖으로 열려 있지 않다. 보려면 [traccar-accessory.md](traccar-accessory.md)의 SSH 터널 방법을 쓴다.

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
export TRACCAR_API_TOKEN=...  TRACCAR_INGEST_TOKEN=...   # 위 5. Traccar 토큰
bin/deploy setup           # 레지스트리 사용자 이름·토큰을 묻는다. 서버 준비, Traccar accessory 기동, 이미지 빌드·push, Rails 컨테이너 기동, 인증서 발급
bin/kamal accessory details traccar   # Traccar가 떠 있는지
bin/kamal app logs         # 부팅 로그
```

`bin/deploy`는 `deploy`·`setup`·`redeploy` 앞에서 `config/credentials/production.key`와 환경변수 `TRACCAR_API_TOKEN`, `TRACCAR_INGEST_TOKEN`이 있는지 확인하고 없으면 이미지를 올리기 전에 멈춘다(없는 채로 올리면 부팅하지 못하는 컨테이너가 만들어진다). 그 밖의 명령(`rollback` 등)은 그대로 `bin/kamal`에 넘긴다.

- 컨테이너가 부팅할 때 `bin/docker-entrypoint`가 `db:prepare`를 실행한다. 빈 DB면 스키마를 만들고, **운영에서는 시드를 실행하지 않는다**(`db/seeds.rb`의 운영 가드). 시드는 데모 계정(`operator@example.com`/`password123`)과 정류장·노선·차량을 만들고 Traccar에도 만들기 때문이다.
- 부팅할 때 `TraccarProductionCheck`가 Traccar 설정을 검사한다. 값이 없거나 개발용(`dev-` 토큰, `iptime.org`·`localhost` 주소)이면 `운영 Traccar 설정 오류: ...`로 부팅이 실패한다. 로그에서 이유를 확인한다.

### 첫 가입자가 운영자다
**배포 직후 가장 먼저 본인이 `https://where-is-my-bus.codefor.kr/registration/new`에서 가입한다.** 첫 가입자가 자동으로 operator가 되고, 가입 폼은 공개되어 있다(`docs/future-improvements.md` 12번). 누가 언제 하는지 미리 정해 둔다. 가입 폼을 닫는 일은 후속 과제다.

### 확인
- `https://where-is-my-bus.codefor.kr/up`이 200이고 인증서가 유효하다.
- 관리자 화면에서 정류장 1개를 등록한다 → Traccar에 Geofence가 생긴다(Traccar 웹 UI에서 확인).
- 차량을 등록하고 운전자 앱으로 PIN 등록·운행을 시작한다. 위치를 보내면 Traccar 이벤트가 도착해 `stop_visits`가 생긴다.
- GA4(`G-V5FQ7DHE99`) 실시간 보고서에 `page_path`와 `arrival_status`가 보인다.

## 이미지 크기와 레지스트리 무료 한도

운영 이미지(arm64, `Dockerfile` 기준)를 실제로 빌드해 쟀다(2026-10-31, Docker Hub·GHCR 공통).

| 항목 | 크기 |
|---|---|
| 로컬 이미지(압축 전) | 약 609 MB |
| **레지스트리에 저장되는 크기**(레이어를 gzip으로 압축한 추정) | **약 219 MB** |
| 코드만 바꾼 다음 배포가 새로 쌓는 양(마지막 `/rails` 레이어만 바뀜) | 약 26 MB |
| `Gemfile.lock`이 바뀐 배포가 새로 쌓는 양 | 위 26 MB + gem 레이어 약 78 MB |

- 레이어별 압축 크기(MB): 기반 Debian 29, Ruby 47, `apt` 패키지 39, gem 78, 앱 26. 재지 않은 것: 레지스트리가 실제로 계산하는 값(위는 `gzip -6` 추정이라 오차가 있다).
- **GitHub 비공개 패키지 무료 한도(GitHub Free: 저장 500MB, 전송 월 1GB)와 비교**: 첫 push 약 219MB는 저장 한도의 44%다. 모든 버전을 남기면 코드만 바꾼 배포 약 10회에서 500MB에 닿는다(`(500−219)/26`). 전송은 서버가 첫 pull 약 219MB + 배포마다 약 26MB를 받으므로 월 1GB로 배포 약 30회다. **단 이 한도는 비공개 패키지에만 해당한다.** 공개 패키지는 무료이고 컨테이너 레지스트리의 저장·대역폭은 문서상 "현재 무료"다(변경 시 최소 1개월 전 공지). 한도가 *압축 크기*로 계산되는지는 문서에서 확인하지 못했다. 압축 전 크기(609MB)로 센다면 한도를 넘는다.
- Kamal은 레지스트리의 옛 버전을 지우지 않는다. 오래된 태그 정리는 따로 해야 한다(Docker Hub 설정 또는 GitHub 패키지 화면).
- **줄일 수 있는 것**: 런타임 `libvips`를 빼면 압축 크기가 약 33MB(15%) 준다(약 186MB). 그러나 앱은 이미지 변환을 쓰지 않는데도 `image_processing` gem이 남아 있어 부팅 때 `Using vips to process variants requires the libvips library` 경고가 나온다(부팅과 `/up`은 정상). `image_processing` gem까지 함께 빼는 것이 먼저다. 지금은 한도 안이라 하지 않았다.
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
- 빈 스토리지 디렉터리를 마운트하고 `RAILS_ENV=production`으로 `db:prepare`를 실행하면 4개 DB가 만들어지고 시드는 실행되지 않으며(`users=0`), 두 번 실행해도 오류가 없다.
- 이미지에 키 파일·`.env`·SQLite·`settings.local.json`·개발용 credentials·문서·테스트·에이전트 디렉터리가 들어 있지 않다.
- Traccar accessory와 같은 설정(환경변수, 네트워크 별칭 `rails-app`)으로 도커 네트워크에서 `geofenceEnter` 이벤트가 `Host: rails-app`, `X-Ingest-Token` 헤더와 함께 도착한다. 수신 쪽은 실제 Rails가 아니라 간이 수신기였다.
- 확인하지 못한 것: 서버 배포, Let's Encrypt 발급, 실제 Rails 컨테이너가 포워딩을 받는지, 호스트 디렉터리 권한, 실기기 운행.
