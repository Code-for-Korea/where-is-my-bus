# Cloudflare Zero Trust Tunnel 준비

서버의 포트를 인터넷에 열지 않고 Cloudflare Tunnel로 필요한 서비스에만 접속하는 방법이다.

**현재 상태: 터널은 아직 없고, Traccar 5055(위치 수신)와 8082(웹/API)를 임시로 게시하고 있다**(`config/deploy.yml`의 Traccar `options.publish`). 8082는 보안 그룹에서 **관리자 IP로만** 연다. 이 문서는 나중에 터널로 옮기고 두 포트를 닫는 절차다. 서버의 `cloudflared`가 Cloudflare로 **바깥 방향 연결만** 만들기 때문에 보안 그룹에 인바운드 규칙을 더하지 않아도 된다.

> 이 문서는 **계획과 절차 초안이다. 실제 서버에 적용해 보지 않았다.** Cloudflare 대시보드의 메뉴 이름과 `cloudflared` 옵션은 바뀔 수 있으니 적용하면서 확인하고 고친다. 적용 전에는 `config/deploy.yml`, `.kamal/secrets`, `bin/deploy`를 바꾸지 않았다.

- 서버 구성과 보안 그룹: [server-spec.md](server-spec.md), [server-setup-ubuntu.md](server-setup-ubuntu.md)
- Traccar accessory: [traccar-accessory.md](traccar-accessory.md)
- 배포 절차: [deployment.md](deployment.md)

## 1. 무엇을 연결하는가

| 용도 | 연결 대상 | 공개 방식 | 우선순위 |
|---|---|---|---|
| Traccar 관리자 화면(8082) | `http://where-is-my-bus-traccar:8082` | Cloudflare Access로 **지정한 사람만** | 높음. 지금은 8082를 관리자 IP로만 열어 둔 임시 상태다 |
| 위치 수신(5055)의 HTTPS 전환 | `http://where-is-my-bus-traccar:5055` | 공개 호스트 이름(로그인 없음) | 높음. 필수 후속 작업(평문 5055 대체) |
| SSH(22) | `ssh://localhost:22` | Cloudflare Access + `cloudflared access ssh` | 선택. 22를 닫고 싶을 때 |

- Rails 웹(80/443)은 기존 kamal-proxy와 Let's Encrypt로 계속 공개한다. 터널로 옮기지 않는다.
- 터널의 공개 호스트 이름은 HTTP(S)만 중계한다. Traccar의 OsmAnd 수신은 HTTP 요청이라 중계할 수 있다고 보지만 **실제 운전자 앱으로 확인하지 않았다.** 확인되기 전에는 5055 게시와 보안 그룹 규칙을 지우지 않는다.
- 위치 수신을 터널로 옮기면 `deviceId`가 오가는 구간이 HTTPS가 되어 [traccar-accessory.md](traccar-accessory.md)의 "HTTPS 전환" 후속 작업을 nginx 없이 해결한다.

## 2. 사전 조건

1. 도메인 `codefor.kr`의 DNS가 **같은 Cloudflare 계정**에 있다(공개 호스트 이름의 CNAME을 Cloudflare가 자동으로 만든다).
2. Cloudflare Zero Trust가 활성화되어 있다. Zero Trust 대시보드의 팀 이름을 정해야 하고 무료 요금제는 사용자 50명까지다. 결제 수단 등록을 요구할 수 있으니 화면에서 확인한다.
3. 서버에서 바깥 방향 443/7844(TCP/UDP)가 막혀 있지 않다. AWS 기본 보안 그룹은 아웃바운드를 모두 허용한다.
4. 관리 권한이 있는 사람이 Cloudflare 계정에 로그인할 수 있다.

## 3. 호스트 이름 정하기

| 호스트 이름 | 대상 | 보호 |
|---|---|---|
| `traccar-admin-where-is-my-bus.codefor.kr` | `http://where-is-my-bus-traccar:8082` | Access 정책(지정 이메일만) |
| `traccar-where-is-my-bus.codefor.kr` | `http://where-is-my-bus-traccar:5055` | 없음(기기가 로그인할 수 없다). 필요하면 WAF 속도 제한 |

`traccar-where-is-my-bus.codefor.kr`는 기존 문서에서 HTTPS 전환용으로 정해 둔 이름이다. 바꾸면 `TRACCAR_SERVER_URL`과 이 문서를 같이 고친다. 이름은 `deploy.yml`에 직접 쓰이지 않고 Cloudflare 대시보드에만 있다.

## 4. 터널 만들기 (원격 관리형)

대시보드에서 터널을 만들면 설정이 Cloudflare에 저장되고 서버에는 **토큰 하나**만 있으면 된다.

1. Zero Trust 대시보드 → Networks → Tunnels → Create a tunnel → Cloudflared.
2. 이름: `where-is-my-bus`.
3. 환경으로 Docker를 고르면 화면에 `--token <긴 문자열>`이 나온다. 이 문자열이 **터널 토큰**이다. 비밀값이다. 대화창, 이슈, PR에 붙이지 않는다.
4. Public Hostname 탭에서 위 표대로 호스트 이름을 추가한다.
   - Subdomain/Domain: `traccar-admin-where-is-my-bus` / `codefor.kr`
   - Service: Type `HTTP`, URL `where-is-my-bus-traccar:8082`
   - 5055도 같은 방식으로 `where-is-my-bus-traccar:5055`를 추가한다.
5. 저장하면 같은 이름의 DNS CNAME(`<터널ID>.cfargotunnel.com`, Proxied)이 자동으로 생긴다.

토큰은 배포 PC의 `.env.deploy`에 `CLOUDFLARE_TUNNEL_TOKEN=...`으로 둔다(파일 권한 `chmod 600`, git에 올리지 않는다). 토큰이 새면 대시보드에서 터널의 토큰을 다시 만들거나 터널을 지운다.

## 5. 서버에 cloudflared 띄우기

### 5.1 Kamal accessory로 (권장)

Traccar와 같은 Kamal 도커 네트워크에 두면 컨테이너 이름(`where-is-my-bus-traccar`)으로 접근한다. `config/deploy.yml`의 `accessories`에 추가할 내용 초안이다.

```yaml
  cloudflared:
    image: cloudflare/cloudflared:2025.11.1   # 적용할 때 최신 태그를 확인해 고정한다
    host: web01.where-is-my-bus
    cmd: tunnel --no-autoupdate run
    env:
      secret:
        - TUNNEL_TOKEN
```

그리고 연결할 곳은 다음과 같다.

- `.kamal/secrets`: `TUNNEL_TOKEN=$CLOUDFLARE_TUNNEL_TOKEN`
- `bin/deploy`: 값 파일 허용 목록(`KAMAL_REGISTRY_USERNAME` 등)에 `CLOUDFLARE_TUNNEL_TOKEN` 추가, 준비 점검 대상에 추가
- 올리기: `bin/deploy accessory boot cloudflared`

적용 때 확인할 것:

- accessory는 기본으로 `kamal` 도커 네트워크에 붙는다. 이 네트워크에서 `where-is-my-bus-traccar`가 이름으로 풀리는지 `docker exec`로 확인한다.
- 포트를 게시하지 않는다(`port:` 없음). cloudflared는 바깥으로만 연결한다.
- 이미지 태그를 고정하되 가끔 올린다. 오래된 버전은 Cloudflare가 지원을 끊을 수 있다.

### 5.2 호스트에 직접 설치(대안)

도커 없이 서버에 `cloudflared`를 apt 또는 deb 패키지로 설치하고 `sudo cloudflared service install <토큰>`으로 systemd 서비스를 만든다. 이때 대상 주소는 컨테이너 이름이 아니라 호스트에서 닿는 주소여야 한다. 지금은 8082와 5055를 호스트에 게시하고 있어 `localhost:8082`, `localhost:5055`로 닿는다. 하지만 게시를 지우는 최종 상태에서는 컨테이너 IP를 써야 해서 번거롭다. 특별한 이유가 없으면 5.1을 쓴다.

## 6. Cloudflare Access로 관리자 화면 보호

`traccar-admin-where-is-my-bus.codefor.kr`는 로그인 없이 열어 두면 안 된다. Traccar 로그인이 있어도 **그 앞에 Access를 한 겹 더 둔다.**

1. Zero Trust → Access → Applications → Add an application → Self-hosted.
2. Application domain: `traccar-admin-where-is-my-bus.codefor.kr`.
3. Policy: Action `Allow`, Include → Emails에 관리자 이메일을 적는다(도메인 전체나 Everyone을 쓰지 않는다).
4. Identity provider: 처음에는 One-time PIN(이메일로 코드 받기)이 설정이 가장 간단하다. 회사 계정이 있으면 Google 등으로 바꾼다.
5. Session duration은 8시간 안팎으로 둔다.

위치 수신 호스트(`traccar-where-is-my-bus`)에는 Access를 걸지 않는다. 기기가 로그인 화면을 통과하지 못해 위치가 끊긴다.

> 관리자 화면은 Access를 통과한 뒤에도 Traccar의 자체 로그인이 있다. 처음 접속할 때 관리자 계정을 만든다. 가입(`WEB_REGISTRATION`)은 꺼 둔 상태를 유지한다.

## 7. 위치 수신을 터널로 옮길 때

1. 터널의 `traccar-where-is-my-bus.codefor.kr` → `http://where-is-my-bus-traccar:5055`를 먼저 만들고 공개한다.
2. 시험: `curl -i https://traccar-where-is-my-bus.codefor.kr`가 400을 돌려주는지 본다(파라미터 없는 요청이라 정상이다. 5055를 직접 호출했을 때와 같은 응답).
3. 한 대의 기기로 `https://traccar-where-is-my-bus.codefor.kr` 주소로 위치를 보내 Traccar에 위치가 쌓이는지 확인한다.
4. `config/deploy.yml`의 `TRACCAR_SERVER_URL`을 `https://traccar-where-is-my-bus.codefor.kr`로 바꾸고 배포한다.
5. 운전자 앱이 평문을 허용하는 목록(`docs/future-improvements.md` 29번)에서 이 서버를 뺄 수 있는지 확인한다.
6. 문제가 없으면 `deploy.yml`의 Traccar `port: "5055:5055"`와 보안 그룹의 5055 규칙을 지우고 다시 배포한다.

기존 기기는 **등록 때 받은 서버 주소**를 쓰므로 주소를 바꾼 뒤 앱이 새 주소를 다시 내려받는지(등록 API가 `TRACCAR_SERVER_URL`을 돌려준다) 확인한다. 이미 등록된 기기가 옛 주소로 계속 보낼 수 있다.

## 8. SSH를 터널로 옮기기 (선택)

22를 보안 그룹에서 닫고 싶을 때만 한다. 서버에서 거치는 길이 `cloudflared` 하나가 되므로 **터널이 죽으면 서버에 못 들어간다.**

- 터널에 호스트 이름(예: `ssh-where-is-my-bus.codefor.kr`) → `SSH`, `localhost:22`를 추가하고 Access 정책을 건다.
- 배포 PC에 `cloudflared`를 설치하고 `~/.ssh/config`를 바꾼다.

```
Host web01.where-is-my-bus
  HostName ssh-where-is-my-bus.codefor.kr
  User ubuntu
  IdentityFile ~/.ssh/<키 파일>.pem
  IdentitiesOnly yes
  ProxyCommand cloudflared access ssh --hostname %h
```

- Kamal은 `~/.ssh/config`의 `ProxyCommand`를 쓸 수 있는지 **확인되지 않았다.** 쓸 수 없으면 `bin/deploy`가 막힌다. 되는 것을 확인하기 전에는 22를 닫지 않는다.
- 닫기 전에 AWS 콘솔의 EC2 Instance Connect나 Session Manager 같은 **다른 접속 수단**이 있는지 확인한다.

## 9. 확인 목록

- [ ] Zero Trust 팀 이름과 요금제가 정해졌다
- [ ] 터널 `where-is-my-bus`가 만들어졌고 토큰이 `.env.deploy`에만 있다(git에 없다)
- [ ] 서버에서 `docker ps`에 `cloudflared` 컨테이너가 Up이고, 대시보드의 터널 상태가 Healthy다
- [ ] `traccar-admin-where-is-my-bus.codefor.kr`가 로그인 없이는 열리지 않고(Access 화면), 허용한 이메일로는 Traccar 로그인 화면이 열린다
- [ ] 허용하지 않은 이메일로는 접속이 거부된다
- [ ] `curl -i https://traccar-where-is-my-bus.codefor.kr`가 400이고 기기 한 대의 위치가 쌓인다
- [ ] 터널로 관리자 화면 접속이 확인된 뒤 `deploy.yml`의 `options.publish`에서 8082를 지우고 보안 그룹의 8082 규칙도 지웠다(Traccar를 다시 부팅해야 게시가 바뀐다: `bin/deploy accessory reboot traccar`, 위치 수신이 잠깐 끊긴다)
- [ ] 5055 게시와 보안 그룹 규칙을 지운 뒤에도 위치가 들어온다
- [ ] 터널이 멈췄을 때 알아차릴 방법(대시보드 상태 알림 등)을 정했다

## 10. 주의

- **터널 토큰은 비밀번호다.** 가진 사람은 같은 터널에 커넥터를 붙일 수 있다.
- 터널은 서버의 `cloudflared` 컨테이너가 살아 있어야 한다. 서버를 중지했다 시작해 IP가 바뀌어도(Elastic IP 보류) 터널은 바깥 방향 연결이라 **IP와 무관하게 다시 붙는다.** 이 점이 터널의 장점이다. 단 Rails 웹의 A 레코드는 여전히 손으로 고쳐야 한다.
- Cloudflare 프록시를 거치면 Traccar가 보는 기기의 IP는 Cloudflare의 IP다. 위치 기록에는 영향이 없지만 IP 기반 제한은 쓸 수 없다.
- 이 서비스(위치 수신)는 Cloudflare에 의존한다. Cloudflare 장애 시 위치 수신이 끊긴다. 그동안 5055를 직접 쓸 수 있게 보안 그룹 규칙을 지우지 않고 두는 방안도 있다(평문 노출을 감수한다).
- 요금제의 한도(사용자 수, 트래픽)는 적용 전에 Cloudflare 문서에서 다시 확인한다.
