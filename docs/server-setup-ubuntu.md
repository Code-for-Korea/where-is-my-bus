# AWS Ubuntu 서버 설치 가이드

Kamal로 배포할 AWS EC2 Ubuntu 서버를 처음 준비하는 절차다. Kamal은 SSH로 서버에 접속해 Docker를 제어하므로 서버에는 **SSH로 접속되는 배포용 사용자**와 **Docker**, 그리고 컨테이너가 쓸 **호스트 디렉터리**만 있으면 된다.

- 구성(인스턴스 크기, 디스크, 가격, 보안 그룹 값): [server-spec.md](server-spec.md)
- 이 서버에 배포하는 절차(credentials, 토큰, `bin/deploy`): [deployment.md](deployment.md)
- 대상 OS: Ubuntu 24.04 LTS (arm64, `t4g.micro` 기준. x86 인스턴스를 쓰면 이미지만 amd64로 고르면 된다)
- 아래 명령의 `<서버IP>`, `<키 파일>` 같은 꺾쇠 값은 환경에 맞게 바꾼다.

> 이 문서는 **실제 서버에서 끝까지 실행해 보지 않았다.** AWS와 Ubuntu 일반 동작에 기대어 적었고, 서버를 만들면서 확인되는 대로 고친다. 특히 Docker 설치 방식과 `kamal setup`의 동작은 첫 서버에서 확인한다.

## 1. 서버 생성 체크리스트

EC2 콘솔(서울 `ap-northeast-2`)에서 인스턴스를 만들 때 확인한다. 값의 근거는 [server-spec.md](server-spec.md)의 "추천 구성"이다.

1. 이름 태그: `Name=where-is-my-bus`
2. AMI: Ubuntu Server 24.04 LTS, **64비트(Arm)** (Canonical 공식 AMI)
3. 인스턴스 유형: `t4g.micro` (모자라면 `t4g.small`)
4. 키 페어: 새로 만들거나 기존 키를 고른다. `.pem` 파일은 배포 PC의 `~/.ssh/`에 두고 권한을 `chmod 600`으로 한다. 잃으면 서버에 접속할 수 없다
5. 네트워크: 보안 그룹 인바운드 규칙
   - 22: **관리자 IP만**
   - 80, 443: 전체 (80은 Let's Encrypt 인증서 발급에 필요하다)
   - 5055: 전체. 첫 배포의 평문 위치 수신용 **임시 규칙**이며 HTTPS 전환 뒤 닫는다([traccar-accessory.md](traccar-accessory.md))
   - 8082(Traccar 웹/API): **관리자 IP만**. 5055와 마찬가지로 임시 규칙이며 HTTPS 전환(관리 화면은 브라우저 인증) 때 닫는다([traccar-accessory.md](traccar-accessory.md) "이름과 구성"). 전체에 열지 않는다
6. 스토리지: gp3 20GB, 암호화 켬
7. 고급 세부 정보: 메타데이터 버전 **V2만(필수)**, 홉 제한 1, 종료 방지 켬
8. 생성 뒤 **Elastic IP**를 할당해 연결한다. 연결하지 않으면 중지 후 시작할 때 IP가 바뀌어 DNS와 SSH 설정을 매번 고쳐야 한다
9. Cloudflare에서 `where-is-my-bus.codefor.kr` A 레코드를 이 IP로 만든다(프록시 끔, DNS only). `dig +short where-is-my-bus.codefor.kr`가 이 IP를 돌려줄 때까지 배포하지 않는다

## 2. 최초 접속과 업그레이드

AWS의 Ubuntu AMI에는 **`ubuntu` 사용자가 이미 있고** 키 페어의 공개키가 등록되어 있다. root 로그인은 막혀 있고 `ubuntu`는 비밀번호 없는 sudo 권한이 있다. 그래서 사용자를 새로 만들 필요가 없다.

```shell
ssh -i ~/.ssh/<키 파일>.pem ubuntu@<서버IP>
```

패키지를 업그레이드하고 재부팅한다.

```shell
sudo apt update
sudo apt upgrade -y
sudo reboot
```

재부팅 뒤 다시 접속한다. 이후 모든 명령은 `ubuntu` 사용자로 실행한다.

### 배포 PC의 `~/.ssh/config`

`deploy.yml`은 서버를 `web01.where-is-my-bus`라는 SSH 별칭으로 부른다. 배포하는 PC마다 아래 항목이 있어야 한다([deployment.md](deployment.md) "SSH 별칭").

```
Host web01.where-is-my-bus
  HostName <서버 IP 또는 Elastic IP>
  User ubuntu
  IdentityFile ~/.ssh/<키 파일>.pem
  IdentitiesOnly yes
```

`IdentitiesOnly yes`가 없으면 SSH 에이전트의 키를 모두 시도하다가 `Too many authentication failures`로 끊길 수 있다. 이제부터는 별칭으로 접속한다.

```shell
ssh web01.where-is-my-bus
```

## 3. 시간대, 기본 패키지, Docker

```shell
sudo timedatectl set-timezone Asia/Seoul
sudo apt install -y docker.io curl git jq sqlite3
```

- `sqlite3`는 `bin/backup-storage`가 쓴다.
- 시간대를 서울로 맞추면 백업 cron 시각이 한국 시각이 된다.

Docker를 부팅 때 자동 시작하고 `ubuntu`가 `sudo` 없이 쓰도록 `docker` 그룹에 넣는다.

```shell
sudo systemctl enable --now docker
sudo usermod -aG docker ubuntu
```

그룹 변경은 **다시 접속해야 적용된다.** 로그아웃 후 접속해서 확인한다.

```shell
docker --version
docker ps
```

`docker ps`가 권한 오류 없이 빈 목록을 보여 주면 정상이다.

> `docker.io`는 Ubuntu 저장소 패키지다. 최신 Docker Engine이 필요하면 [Docker 공식 문서](https://docs.docker.com/engine/install/ubuntu/)의 apt 저장소 설치 방법을 쓴다. Kamal은 `docker`가 없으면 `kamal setup`에서 설치를 시도하지만 Ubuntu에서의 동작은 확인하지 못했다. 미리 설치해 두는 편이 확실하다.

### 컨테이너 로그 크기 제한

컨테이너 로그가 디스크를 채우지 않게 한다.

```shell
sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
sudo systemctl restart docker
```

Kamal이 컨테이너를 만들 때 로그 옵션을 따로 주는지는 확인하지 못했다. 중복되어도 문제는 없다.

## 4. 데이터 디렉터리

`config/deploy.yml`의 `volumes`가 마운트하는 호스트 경로를 미리 만든다.

```shell
sudo mkdir -p /var/lib/where-is-my-bus/storage /var/lib/where-is-my-bus/traccar
sudo chown 1000:1000 /var/lib/where-is-my-bus/storage
sudo mkdir -p /var/backups/where-is-my-bus
```

- Rails 컨테이너는 uid/gid **1000**(`rails`)으로 돈다. 소유자는 이름이 아니라 **숫자 1000:1000**으로 맞춘다. `ubuntu` 사용자의 uid는 보통 1000이지만 이미지에 따라 다를 수 있으므로 `id ubuntu`로 확인하되, 항상 숫자로 지정한다.
- 이 디렉터리를 만들지 않고 배포하면 Docker가 root 소유로 만들어 Rails가 쓰지 못한다. 컨테이너가 `db:prepare`에서 권한 오류로 뜨지 않는다.
- SQLite는 DB 파일뿐 아니라 WAL/SHM 파일을 만들 디렉터리에도 쓰기 권한이 필요하다.
- `traccar` 디렉터리는 Traccar 컨테이너가 root로 돌아 소유자를 바꿀 필요가 없다.

확인과 복구:

```shell
ls -lan /var/lib/where-is-my-bus
sudo chown 1000:1000 /var/lib/where-is-my-bus/storage
```

## 5. 스왑 파일 (2GB)

`t4g.micro`(1GiB)는 평상시에 빠듯하고 배포하는 순간 메모리가 넘친다. 스왑을 안전망으로 둔다([server-spec.md](server-spec.md) "1GB로 되는가", "스왑을 쓰면"). Ubuntu AMI에는 스왑이 없다.

```shell
swapon --show          # 이미 스왑이 있는지 확인(비어 있어야 한다)
free -h                # 메모리 사용량
df -h /                # 디스크 남은 용량

sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 재부팅 뒤에도 유지
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

swapon --show
free -h
```

`swappiness`는 기본값(60)으로 두고 관찰한다.

## 6. 보안 기본 설정

### 6.1 SSH 설정

별칭(`ssh web01.where-is-my-bus`)으로 접속이 되고 `sudo -n true`가 성공하는 것을 **확인한 뒤에만** 적용한다. 비밀번호 로그인을 막고 접속 사용자를 제한한다.

```shell
sudo tee /etc/ssh/sshd_config.d/60-hardening.conf > /dev/null <<'EOF'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AllowUsers ubuntu
EOF

sudo sshd -t && sudo systemctl restart ssh
```

> 적용 뒤 **기존 세션을 닫지 말고** 새 터미널에서 `ssh web01.where-is-my-bus`가 되는지 확인한다. 실패하면 기존 세션에서 파일을 지워 복구한다.
> `sshd_config.d`는 파일 이름 순서로 읽히고 먼저 읽힌 값이 우선한다. `sudo sshd -T | grep -iE 'passwordauth|permitroot'`로 최종 값을 확인한다.

### 6.2 방화벽

AWS 보안 그룹이 1차 방화벽이다. 서버의 UFW는 쓰지 않아도 된다. 쓴다면 SSH를 **먼저 허용한 뒤** 활성화한다.

```shell
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 5055/tcp
sudo ufw enable
sudo ufw status
```

> Docker는 게시한 포트(Traccar의 5055)를 UFW보다 먼저 iptables에 등록한다. UFW만으로는 컨테이너 포트 노출이 막히지 않으므로 **노출 제어는 보안 그룹을 기준으로** 한다. 5055를 막으려면 보안 그룹 규칙을 지운다.

## 7. 로컬에서 접속 확인

배포 PC에서:

```shell
ssh web01.where-is-my-bus docker ps
```

`docker ps`가 비밀번호나 `sudo` 없이 돌아야 Kamal이 이 서버를 다룰 수 있다.

## 8. Kamal 연동

- `config/deploy.yml`은 이미 `web01.where-is-my-bus`와 `servers.web.hosts`, `accessories.traccar.host`를 쓴다. `ssh.user: ubuntu`로 접속 사용자를 정한다(`~/.ssh/config`의 `User`보다 우선한다).
- `builder.arch`는 `arm64`다. `t4g`(Graviton)에 맞다. x86 서버를 쓰면 `amd64`로 바꾼다.
- 이어서 [deployment.md](deployment.md)의 절차(운영 credentials, Traccar 토큰, GitHub 토큰, `bin/deploy setup`)를 따른다.

```shell
# 최초 1회: Docker 확인, kamal-proxy 설치, 앱과 Traccar 배포
bin/deploy setup

# 이후 배포
bin/deploy
```

## 9. 검증 체크리스트

- [ ] `ssh ubuntu@<서버IP>`가 키로 접속된다. root와 비밀번호 로그인은 거부된다
- [ ] `sudo -n true`가 성공한다
- [ ] `docker ps`가 `sudo` 없이 동작한다
- [ ] `swapon --show`에 2GB 스왑이 보인다
- [ ] `/var/lib/where-is-my-bus/storage`의 소유자가 `1000:1000`이다
- [ ] `timedatectl`이 `Asia/Seoul`이다
- [ ] 배포 PC에서 `ssh web01.where-is-my-bus docker ps`가 성공한다
- [ ] 보안 그룹이 22(관리자 IP만), 80, 443, 5055(임시), 8082(임시, 관리자 IP만)이다
- [ ] Elastic IP가 연결되어 있고 `dig +short where-is-my-bus.codefor.kr`가 그 IP를 돌려준다
- [ ] `bin/deploy setup` 뒤 `https://where-is-my-bus.codefor.kr/up`이 200이다
