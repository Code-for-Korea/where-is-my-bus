# AWS 서버 운영 (생성, 껐다 켜기, Discord 제어, IP 변경)

Rails와 Traccar를 **한 서버**에 올리고(Kamal, [traccar-accessory.md](traccar-accessory.md)), 비용 때문에 서버를 껐다 켜며, 제어는 **Discord**에서 하는 구성을 정리한다. Kamal 배포 절차는 [deployment.md](deployment.md)다.

> **설계 문서이고 구현·실행한 것이 없다**(Traccar accessory 설정만 `config/deploy.yml`에 반영됨). 이 프로젝트용 AWS 계정·서버·Discord 앱·Lambda는 아직 없다. AWS 동작과 Discord API는 일반 지식이라 적용 전에 콘솔과 공식 문서로 확인한다. 확인한 것과 못 한 것은 맨 아래에 나눠 적었다.

## 1. 참고한 구현 (Slack으로 EC2 제어)

다른 프로젝트에서 Slack 슬래시 명령으로 스테이징 EC2를 켜고 끄는 구현(Lambda 하나, Python, boto3, 표준 라이브러리만)을 읽고 참고했다. 이 저장소에는 가져오지 않았다. 구조는 다음과 같다.

- Slack 명령 → API Gateway(HTTP API) → Lambda. 서명을 검증하고, 3초 안에 "처리 중..."만 응답한 뒤 **자기 자신을 비동기 호출**한 워커가 EC2를 제어하고 `response_url`로 결과를 보낸다.
- `start`하면 EventBridge Scheduler가 2시간 뒤 중지를 예약한다. 서버는 EC2 `Name` 태그로 찾는다.
- Lambda는 VPC에 붙이지 않는다(EC2 API만 호출. 붙이면 NAT 없이 호출이 멈춘다).
- 그 구현에는 서버를 **만드는** 자동화가 없다(Terraform, `run-instances` 없음). 서버는 사람이 만들고, 스테이징은 사설 IP로 접속해서 공인 IP 변경 문제가 없다.

Discord는 같은 구조를 거의 그대로 쓸 수 있다. 다른 점만 아래에 적는다.

## 2. Discord로 제어하기

### 방식

Discord **슬래시 명령 + Interactions Endpoint URL**을 쓴다. 서버 안에서 24시간 도는 봇(Gateway)은 쓰지 않는다. 제어 대상 서버가 꺼져 있을 수 있어 봇을 거기에 둘 수 없고, 상시 도는 봇은 그 자체가 비용이다. 요청이 올 때만 도는 Lambda가 맞다.

```
Discord /server start → (Discord가 HTTPS POST) → API Gateway → Lambda
  ├ Ed25519 서명 검증 (헤더 X-Signature-Ed25519, X-Signature-Timestamp)
  ├ PING(type 1)에는 {"type":1} 응답 (엔드포인트 URL을 저장할 때 Discord가 보낸다)
  ├ 3초 안에 "처리 중"(type 5, deferred) 응답
  ├ 자기 자신을 비동기 호출 → EC2 start/stop → interaction token으로 결과 메시지 전송
  └ (선택) EventBridge Scheduler로 정해진 시각에 켜고 끄기
```

### Slack 방식과 다른 점

| 항목 | Slack | Discord |
|---|---|---|
| 서명 검증 | HMAC-SHA256, 표준 라이브러리 | **Ed25519**. Python 표준 라이브러리에 없다. **Node.js 런타임**(내장 `crypto`가 Ed25519 검증 가능) 또는 Python + PyNaCl 레이어가 필요하다 |
| 응답 | `response_url`로 보냄 | `PATCH /webhooks/{application_id}/{interaction_token}/messages/@original`. 토큰은 15분 유효 |
| 명령 등록 | Slack 앱 화면에서 입력 | **REST로 한 번 등록**한다(길드 명령은 바로 반영). 봇 토큰이 이때만 필요하다 |
| 서버 고르기 | 문자열 인자 | 명령 옵션에 **선택지(choices)** 를 줄 수 있다 |
| 앱당 URL | 명령마다 URL 가능, Interactivity는 1개 | **앱당 Interactions URL 1개.** 이 프로젝트는 AWS 계정이 하나라 문제없다 |
| 참고 구현 재사용 | 그대로 쓸 수 있음 | 서명 검증과 응답 부분을 새로 써야 한다. EC2 제어·스케줄 로직은 같은 방식으로 만들 수 있다 |

### 권한 (결정: 운영자만 쓸 수 있게 제한한다)

서명 검증은 "Discord가 보낸 요청"임만 보장한다. 제한하지 않으면 **채널에 들어온 누구든** 서버를 끌 수 있다. 아래를 **모두** 적용한다.

1. **길드 제한**: payload의 `guild_id`가 우리 Discord 서버의 ID(환경변수 `ALLOWED_GUILD_ID`)가 아니면 거부한다. 앱을 다른 서버에 초대해도 동작하지 않는다.
2. **역할 제한**: payload의 `member.roles`에 허용 역할 ID(환경변수 `ALLOWED_ROLE_IDS`, 쉼표 구분)가 하나도 없으면 거부한다. 거부는 본인에게만 보이는 메시지(ephemeral)로 한다. 서버 소유자나 관리자 권한자도 이 역할이 없으면 막는 쪽이 단순하고 안전하다.
3. **명령 숨김**: 명령 등록 때 `default_member_permissions`를 걸어 일반 멤버에게는 명령이 보이지 않게 한다. 이것만으로는 보안이 아니다(서버 관리자가 바꿀 수 있다). 1, 2가 실제 방어다.
4. **상태 조회와 변경을 나눈다**: `status`는 운영자 역할이면 누구나, `start`/`stop`은 더 좁은 역할(예: 배포 담당)만 쓰게 하는 안을 선택할 수 있다. 처음에는 역할 하나로 시작한다.
5. **기록**: 누가 무엇을 했는지 `user.id`와 명령을 CloudWatch 로그와 채널 메시지에 남긴다(참고 구현의 "실행자 표시"와 같다).
6. **운행 중 `stop`**: 진행 중인 운행(`Trip.ended_at`이 nil)이 있으면 거부하고, 강제하려면 `stop force`처럼 명시한다. 이 판단에는 Rails의 정보가 필요하고 서버가 켜져 있을 때만 알 수 있다. Lambda가 앱에 묻는 방식은 운행 상태를 돌려주는 인증된 엔드포인트를 Rails에 새로 만들어야 한다(`/up`은 운행 정보를 주지 않는다). 우선은 `stop` 때 "운행 중인 버스를 확인했는가" 문구만 두는 방식도 가능하다. 어느 쪽으로 할지는 결정 대기다.
7. **서명 검증 실패**: 서명이 틀리면 401(PING도 서명 검증 뒤에 응답). 비밀성 있는 값(`DISCORD_PUBLIC_KEY`, 허용 ID, 나중에 DNS 자동 갱신을 쓰면 Cloudflare 토큰)은 환경변수 대신 SSM Parameter Store나 Secrets Manager에 둔다.

Discord 쪽 설정은 사람이 해야 한다: 애플리케이션 생성, Public Key 확인, 길드에 설치, 역할 만들기, 명령 등록(봇 토큰은 등록할 때만 쓰고 Lambda에는 넣지 않는다).

### 명령 초안

```
/server status            상태, 공인 IP, 앱 응답(/up) 여부
/server start             서버를 켠다
/server stop              서버를 끈다
```

서버가 1대라 서버 이름 인자는 필요 없다. 여러 대가 되면 `Name` 태그 선택지를 추가한다.

### 참고 구현에서 바꿀 점

| 참고 구현의 동작 | 이 프로젝트 |
|---|---|
| `start` 2시간 뒤 **무조건 중지** | **제거한다.** 승객이 쓰는 서버를 2시간 뒤에 끄면 서비스가 멈춘다. 대신 아래 3장의 정해진 시간표를 쓴다 |
| 상태에 `running` 같은 상태만 표시 | 공인 IP(`describe_instances`의 `PublicIpAddress`)와, 켠 뒤 **앱이 실제로 응답하는지**(`https://where-is-my-bus.codefor.kr/up`)를 함께 보여 준다. EC2가 `running`이어도 Docker·Rails가 뜨기까지 시간이 걸린다 |
| 시작 요청만 하고 끝남 | 시작 후 `running`이 될 때까지 기다렸다가 결과를 보낸다(Lambda 최대 15분 안) |
| `list_schedules` 100개 한 번 조회 | 자동 중지 예약을 없애면 해당 코드 자체가 사라진다 |

필요한 권한은 `ec2:Start/Stop/DescribeInstances`(가능하면 `Resource`를 이 인스턴스 ARN으로 한정), `lambda:InvokeFunction`(자기 호출), 로그다. 참고 구현은 `*`로 열어 두었는데 여기서는 좁힌다.

## 3. 비용 때문에 껐다 켜기

### 켜고 끄는 방식: 시간표와 수동을 둘 다 검토

| | 정해진 시간표 (EventBridge Scheduler cron, `Asia/Seoul`) | 수동 (Discord `start`/`stop`) |
|---|---|---|
| 운행 시간이 일정할 때 | 사람 손이 없다. 잊어서 켜 둔 채 비용이 나가거나 필요한 때 꺼져 있는 일이 없다 | 사람이 매번 해야 한다. 잊으면 서비스가 멈추거나 비용이 샌다 |
| 시간이 들쭉날쭉할 때(임시 운행, 시험) | 시간표 밖은 못 쓴다. 예외마다 시간표를 고쳐야 한다 | 유연하다 |
| 장애·실수 | 서버 문제로 켜지지 않으면 운행 시간에도 꺼져 있다. **알림이 필요하다** | 켜는 사람이 확인한다 |
| 비용 | 켜 두는 시간이 고정되어 예측된다 | 사람에 따라 변한다 |
| 만들 것 | 스케줄 2개(켜기, 끄기) + 실패 알림 | 명령 3개 |

**추천: 둘을 함께 쓴다.** 운행 시간표대로 스케줄이 켜고 끄고, Discord는 예외(시간표 밖에 켜기, 일찍 끄기, 상태 확인)에만 쓴다.

- 스케줄이 켠 것을 사람이 끄거나, 사람이 켠 것을 스케줄이 끄는 충돌을 정해 둔다. 제안: **스케줄은 정해진 끄는 시각에 항상 끈다**(사람이 연장하려면 그날 `stop`을 막는 대신 스케줄의 끄는 시각을 미룬다). 단순하게 하려면 처음엔 수동만 하고, 운행 시간이 굳으면 스케줄을 추가한다.
- 끄기 직전에 백업이 돌고, 끄기 직전에 운행 중인 버스가 있는지 확인한다([traccar-accessory.md](traccar-accessory.md) "데이터와 백업", "껐다 켤 때의 위험").
- 운행 시간표(켜는 시각, 끄는 시각)는 아직 모른다. 정해지면 이 문서에 적는다.

### 비용이 어떻게 바뀌는가

- **중지된 인스턴스는 컴퓨팅 요금이 없다.** EBS 디스크 요금은 계속 나간다.
- 자동 할당 공인 IPv4는 인스턴스가 켜져 있는 동안만 쓰이고 중지하면 사라진다(그래서 IP가 바뀐다). **Elastic IP는 중지 중에도 요금이 나간다**(서울 기준 공인 IPv4는 사용 중이든 놀고 있든 시간당 $0.005, 아래 가격표). 껐다 켜는 목적이 비용 절감이면 Elastic IP 요금이 절감분을 일부 깎는다.
- Discord 제어용 Lambda, API Gateway, EventBridge Scheduler는 이 규모에서 무료 한도 안일 가능성이 높다(확인하지 못함).

### 서버가 꺼져 있는 동안과 켠 직후

- 위치 수신, 이벤트 수신, 승객 화면이 모두 멈춘다. 운행 시간을 덮도록 시간표를 정한다.
- 켠 직후: EC2 부팅 → Docker → kamal-proxy·Rails·Traccar 컨테이너 순으로 뜬다. Kamal은 이 컨테이너들을 `--restart unless-stopped`로 띄우므로(Kamal 2.11 소스 확인) 부팅 후 스스로 올라온다. **실제 소요 시간과 순서는 첫 시험에서 재야 한다.**
- 보내지 못한 위치를 앱이 모았다가 켜진 뒤 한꺼번에 보내는지는 [traccar-accessory.md](traccar-accessory.md)의 "껐다 켤 때의 위험"을 본다.
- 백업은 **서버가 켜져 있을 때** 돈다. 끄기 직전에 백업을 걸면 자연스럽다([traccar-accessory.md](traccar-accessory.md) "데이터와 백업").

## 4. 껐다 켜면 IP가 바뀌는 문제

### 무엇이 바뀌고 남는가 (AWS 일반 동작)

| 항목 | 중지 후 시작 | 재부팅 |
|---|---|---|
| 공인 IPv4 (자동 할당) | **바뀐다** | 유지 |
| 공인 IPv4 (Elastic IP) | 유지 | 유지 |
| 사설 IPv4 | 유지 | 유지 |
| EBS 디스크(`/var/lib/where-is-my-bus`) | 유지 | 유지 |
| 인스턴스 스토어 디스크 | 사라진다 | 유지 |

SQLite와 Traccar H2는 EBS에 있으므로 껐다 켜도 남는다. 인스턴스 스토어 타입은 고르지 않는다.

### IP가 바뀌면 깨지는 것

이제 **운전자 앱도 영향을 받는다.** 위치 수신 주소(`TRACCAR_SERVER_URL`)가 이 서버이기 때문이다.

1. `where-is-my-bus.codefor.kr` A 레코드가 옛 IP를 가리킨다. 승객 화면, Traccar 위치 수신(5055) 둘 다 끊긴다. 앱이 IP가 아닌 **도메인**으로 보내므로 DNS만 맞으면 앱 설정은 그대로다.
2. Let's Encrypt 인증서 갱신은 DNS가 맞아야 한다. 이 도메인의 DNS는 Cloudflare다(NS가 `*.ns.cloudflare.com`임을 확인함).
3. `deploy.yml`의 `servers.web`(IP)과 Kamal accessory의 `host`가 옛 IP를 가리킨다. SSH `known_hosts`도 어긋난다.
4. Rails ↔ Traccar는 서버 안 도커 네트워크로 통신하므로 **영향이 없다**(이 구성의 장점).

### 해결 방법

| 방법 | 내용 | 장단점 |
|---|---|---|
| **A. Elastic IP (권장 시작점)** | 고정 IP를 인스턴스에 붙이고 DNS A 레코드를 한 번만 만든다 | 가장 단순하고 DNS·`deploy.yml`·SSH가 안 바뀐다. 중지 중에도 IPv4 요금이 나간다(월 약 $3.65). 인스턴스에 안 붙은 EIP는 반납한다 |
| B. **Discord Lambda가 시작 때 DNS 갱신** | 시작 후 `running`이 되면 Lambda가 새 공인 IP를 Cloudflare API로 A 레코드에 쓰고, 결과 메시지에 IP를 함께 보낸다 | IPv4 요금이 없다. 하지만 Discord·스케줄러 외의 경로로 켜면(콘솔 등) 갱신이 안 된다. **Cloudflare API 토큰이 Lambda에 들어간다.** 토큰은 `codefor.kr` zone의 DNS 편집으로 범위를 좁히되 레코드 하나로는 못 좁힌다. 짧은 TTL(60초)이 필요하고 갱신 전 수십 초는 접속이 안 된다 |
| C. EventBridge 상태 변경 규칙 → Lambda가 DNS 갱신 | EC2가 `running`이 될 때마다(어떤 경로로 켜도) 갱신 | B의 빈틈이 없다. Lambda를 하나 더 둔다 |
| D. Cloudflare Tunnel | `cloudflared`가 밖으로 연결해 공인 IP 자체가 필요 없다 | HTTP(S)만 터널로 가고 **5055(OsmAnd)는 다른 처리**가 필요하다. TLS 종단도 달라져 kamal-proxy 구성을 바꿔야 한다. 이번 범위를 넘는다 |

**결정 (추천 채택): 처음엔 A(Elastic IP)로 시작**한다. 이유: ① 껐다 켜기, Discord Lambda, 시간표 스케줄이 모두 새로 만들어지는 중이라 IP 문제를 같이 만들 이유가 없다. ② DNS 자동 갱신(B, C)은 Cloudflare 토큰과 Lambda가 추가로 필요하고, 갱신 전 수십 초 동안 위치 수신이 끊기며 앱이 그동안 보낸 위치가 어떻게 되는지 아직 모른다. ③ 비용 차이는 월 $3.65(Elastic IP 24시간)에서 켜진 시간만큼(자동 IP)을 뺀 값이다. 12시간 켜면 약 $1.83, 24시간 켜면 차이가 없다(6장 가격표). 한 달 정도 운영해 보고 IPv4 요금이 신경 쓰이면 **C**(없으면 B)로 옮긴다. 그때 `servers.web`은 호스트명으로 바꿔 둔다. `servers.web`을 IP 대신 **호스트명**으로 적으면 IP가 바뀌어도 `deploy.yml`을 안 고친다(그 이름의 Cloudflare 레코드는 프록시를 끈 상태여야 SSH가 된다).

### 켠 뒤 확인

```bash
dig +short where-is-my-bus.codefor.kr                                          # 새 서버 IP와 같은지
curl -sS -o /dev/null -w '%{http_code}\n' https://where-is-my-bus.codefor.kr/up # 200
bin/kamal app details && bin/kamal accessory details traccar            # Rails와 Traccar가 모두 떠 있는지
```

처음 한 번은 직접 껐다 켜 보고 위 세 가지가 사람 손 없이 되는지 확인한다(하지 못함).

## 5. AWS CLI로 확인·제어 (Discord 없이)

```bash
aws sts get-caller-identity                     # 어느 계정인지 먼저 확인
aws ec2 describe-instances --filters "Name=tag:Name,Values=where-is-my-bus" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress]' --output table
aws ec2 start-instances --instance-ids <i-...> && aws ec2 wait instance-running --instance-ids <i-...>
aws ec2 stop-instances  --instance-ids <i-...>
```

## 6. EC2 구성 추천과 서버 생성

참고 구현에 서버 생성 자동화가 없다. 서버 1대라 **콘솔 + 아래 구성**으로 충분하다. 같은 서버를 다시 만들 일이 잦아지면 AWS CLI 스크립트로 옮기고, Terraform은 서버가 늘 때 검토한다.

### 크기: 실측으로 정했다

운영 이미지를 로컬 도커에서 띄워 잰 값이다(`docker stats`). 실제 운영 부하(기기 여러 대의 위치 수신, 승객 접속)에서의 값이 아니다.

| 구성요소 | 측정값 | 조건 |
|---|---|---|
| Rails 컨테이너 (Thruster + Puma 1프로세스·3스레드 + Solid Queue 내장, jemalloc) | **약 200 MiB** (부팅 직후) → **약 256 MiB** (홈과 소개 페이지 120회 요청 뒤) | arm64 이미지, 빈 DB |
| Traccar 컨테이너 | **약 266 MiB** | 로컬에서 3일 동안 켜 둔 컨테이너, 기기 없음, 유휴 |
| kamal-proxy | **약 3.5 MiB** | 유휴, 이미지 `basecamp/kamal-proxy:v0.9.2` |
| Ubuntu + Docker 데몬 | 재지 않음(이 PC는 macOS라 잴 수 없다) | 서버에서 `free -m`으로 확인한다 |
| 배포 중 | Rails가 **잠깐 2개**(새·옛 컨테이너) | 약 256 MiB가 더 얹힌다 |

- Rails + Traccar만 약 520 MiB, 배포 중에는 약 780 MiB다. 여기에 OS와 Docker 데몬이 얹히므로 **1GB는 부족**하고 **2GB가 맞다.** (OS·Docker 몫은 재지 않았으므로 2GB에서의 여유도 첫 서버에서 `free -m`, `docker stats`로 확인한다.)
- **Traccar는 힙 상한이 없다.** 이미지의 실행 명령이 `java -jar tracker-server.jar`뿐이라(`-Xmx` 없음) JVM 기본값(메모리의 일부)까지 커질 수 있다. 기기가 늘면 266 MiB보다 커진다. 운행 중 `docker stats`로 본다.
- **Traccar 힙을 제한해도 유휴 메모리는 거의 줄지 않는다.** 같은 이미지에 `JAVA_TOOL_OPTIONS="-Xmx128m -Xss512k -XX:+UseSerialGC"`(JVM이 인식함을 로그로 확인)를 주고 재니 기본 설정 약 236 MiB, 제한 설정 약 231 MiB였다. 유휴에서는 힙이 아니라 JVM 고정 부분이 대부분이라는 뜻이다. 힙 제한은 기기가 늘었을 때의 상한을 막는 용도다.
- 운영 이미지의 `WEB_CONCURRENCY`는 비어 있어 Puma는 1프로세스다. 워커를 늘리면 Rails 메모리가 그만큼 늘어나므로 2GB 안에서는 늘리지 않는다.

### 1GB(`t4g.micro`)로 되는가

**평상시는 빠듯하게 들어가고, 배포하는 순간은 넘친다. 안정 운영용으로는 부족하다고 본다. 단 스왑을 쓰면 가능성은 있다(바로 아래 "스왑을 쓰면").**

| 항목 | 값 | 근거 |
|---|---|---|
| 컨테이너 합계(평상시) | 약 500~530 MiB | Rails 약 256 + Traccar 약 236~266 + kamal-proxy 약 3.5, 모두 측정 |
| OS + Docker 데몬 + sshd | 약 300 MiB로 **가정** | 측정하지 못했다(서버에서 확인) |
| 1GiB 인스턴스에서 쓸 수 있는 메모리 | 약 900 MiB대 | 커널 예약분을 뺀 일반 지식 |
| 평상시 여유 | 약 70~100 MiB | 위 값으로 계산 |
| 배포 중 | 새 Rails 컨테이너가 추가로 약 256 MiB(+부팅 때 순간 증가) | **여유를 넘는다** → 스왑에 의존하거나 OOM 위험 |

- Kamal은 새 컨테이너를 띄우고 헬스체크가 통과한 뒤 옛 컨테이너를 내리므로 겹침을 피할 수 없다. 스왑 2GB가 있으면 배포는 되겠지만 그동안 디스크로 밀려 느려지고(gp3 기본 성능에서는 느린 것이지 멈추는 것은 아니다), 가장 큰 프로세스인 Traccar가 OOM으로 죽을 수 있다. 그동안 위치를 못 받는다.
- 실제 운영 부하(기기가 붙은 Traccar, 승객이 접속한 Rails)는 위 측정보다 클 것이다. Traccar는 힙 상한이 없어 기기가 늘면 더 커진다.
- 절감액은 작다: `t4g.micro`는 `t4g.small`보다 **월 $7.59**($0.0104 대비 $0.0208), 하루 12시간만 켜면 약 $3.8이다. 메모리를 아껴서 얻는 이익에 비해 위치 누락 위험이 크다.
- **결정(2026-10-31): `t4g.micro` + 스왑 2GB로 시작한다.** 위험을 알고 택한 것이므로 아래 "승격 기준"으로 `t4g.small`로 올릴 시점을 정해 둔다. 크기는 서버를 한 번 껐다 켜서(중지 → 유형 변경 → 시작) 바꿀 수 있어 되돌리는 비용이 작다.

### 스왑을 쓰면 (측정)

메모리 한도를 걸어 스왑을 강제로 쓰게 한 컨테이너로 확인했다. **이 PC의 도커 VM(Apple Silicon, cgroup v2)이라 디스크가 EBS보다 훨씬 빠르다. 낙관적인 하한으로만 읽는다.**

| 대상 | 조건 | 결과 |
|---|---|---|
| Traccar (JVM `-Xmx128m`, SerialGC) | RAM 한도 140 MiB, 스왑 허용 | **141 MiB가 스왑으로 나감**(전체의 절반 이상), OOM 0, 응답 정상. 30초 유휴 뒤 첫 요청 61ms(기준선 37ms), 이후 3~10ms |
| Rails (운영 이미지) | RAM 한도 150 MiB, 스왑 허용 | **182 MiB가 스왑으로 나감**, OOM 0, 모두 200. 유휴 뒤 첫 요청 41ms(기준선 21ms). 60회 요청 중앙값 5ms(4ms), p95 17ms(11ms), 최대 123ms(46ms) |

읽는 법:
- **오래 안 쓰는(차가운) 메모리를 스왑으로 내보내는 것은 싸다.** 위 두 경우는 메모리의 절반 이상을 내보냈는데도 지연이 눈에 띄게 늘지 않았다. 배포 중에 **옛 Rails 컨테이너가 유휴로 남는 상황**이 정확히 이 경우라서 스왑이 겹침 비용을 흡수해 줄 가능성이 높다.
- **작업 중인 메모리(working set)가 RAM보다 크면 이야기가 다르다.** 이 시험은 가벼운 페이지 요청만 보냈고, DB를 많이 쓰는 요청, 기기가 붙은 Traccar, 가비지 컬렉션(JVM이 힙을 훑는다)이 겹치는 부하는 시험하지 못했다. 그런 상황에서 디스크 스왑은 급격히 느려진다(thrashing).
- **EBS는 이 시험보다 느리다**(gp3 기본 3000 IOPS, 무작위 읽기 지연이 로컬 SSD보다 훨씬 큼). 측정하지 못했다.
- T 계열은 메모리 압박에서 커널 CPU를 쓰므로 **CPU 크레딧이 줄 수 있다**(일반 지식).
- 스왑 파일 자체는 거의 공짜다: 2GB는 gp3 기준 월 약 $0.18(GB당 $0.0912).

결론: **스왑은 어느 크기에서든 안전망으로 둔다(2GB 파일).** 1GB 인스턴스에서는 스왑으로 평상시 + 배포가 돌아갈 가능성이 있지만 확정은 서버에서만 가능하다. 서버에서 `vmstat 1`의 `si`/`so`(스왑 입출력), `free -m`, CloudWatch `CPUCreditBalance`와 배포 한 번의 `dmesg | grep -i oom`을 보고 정한다. 압축 메모리 스왑(zram)도 선택지이지만 AWS용 우분투 커널에서의 가용성은 확인하지 못했다.

### 1 vCPU, `t2.micro`는 되는가

**`t2.micro`를 고를 이유가 없다.** 1GiB라서 위 메모리 문제는 그대로이고, 더 비싸며, 한 세대 전이다.

| 인스턴스 | vCPU / 메모리 | 시간당 | 월(730h) | CPU |
|---|---|---|---|---|
| `t2.micro` | 1 / 1GiB | $0.0144 | $10.51 | Intel Xeon(이전 세대) |
| `t3.micro` | 2 / 1GiB | $0.0130 | $9.49 | Intel Skylake |
| **`t4g.micro`** | 2 / 1GiB | **$0.0104** | **$7.59** | Graviton2 |

(서울 온디맨드 Linux, 2026-10-29 공시.) 같은 1GiB인데 `t2.micro`가 vCPU는 절반이고 가격은 더 높다. 1GB로 가려면 `t4g.micro`가 가장 싸다.

- **vCPU 1개 자체의 영향은 작아 보인다.** 같은 Rails 이미지를 CPU 1개로 제한해 재니 부팅 약 2.7초(제한 없음 약 2.6초), 60회 요청 중앙값 7ms(제한 없음 9ms), 4개 동시 클라이언트에서 p95 92ms였다. 다만 **이 Mac의 코어는 `t2.micro`의 코어보다 훨씬 빠르다.** 절대값으로는 믿지 말고 "1개 코어로도 가벼운 요청은 문제없다" 정도로만 읽는다.
- **실제 제약은 코어 수가 아니라 크레딧과 메모리다.** T 계열은 기준 성능(`t2.micro`는 vCPU당 10%로 알고 있다) 이상을 쓰려면 크레딧이 필요하다. `t2`는 기본이 크레딧이 떨어지면 성능이 제한되는 방식(standard)이고 `t3`/`t4g`는 초과분에 요금이 붙는 방식(unlimited)이 기본이라고 알고 있다(둘 다 일반 지식, 확인하지 못함). 배포 순간에 Rails 부팅, Traccar, Docker 데몬이 코어 하나를 나눠 쓴다.
- `t2`는 x86이라 `builder.arch: amd64` 그대로 쓸 수 있다는 것이 유일한 장점이다. 그 장점은 `t3.micro`/`t3.small`도 같다.

### ARM(`t4g`)과 x86(`t3`, `t3a`, `t2`) 비교

**설치할 라이브러리 문제는 찾지 못했다. 두 아키텍처 모두 실제로 빌드하고 실행해서 확인했다.**

| | ARM (`t4g.small`) | x86 (`t3.small`, `t3a.small`) |
|---|---|---|
| 가격(2GiB) | **$15.18/월** | `t3a` $17.08, `t3` $18.98 |
| Rails 이미지 빌드 | **성공**(이 Mac에서 네이티브) | **성공**(`--platform linux/amd64`, 에뮬레이션, 종료 코드 0) |
| Rails 이미지 실행 | 부팅, `/up` 200, Ruby `aarch64-linux` | 부팅, `/up` 200, Ruby `x86_64-linux`(에뮬레이션 실행) |
| 미리 빌드된 gem | `ffi`, `nokogiri`, `sqlite3`, `tailwindcss-ruby`, `thruster`에 `aarch64-linux` 판이 `Gemfile.lock`에 있음 | 같은 gem들에 `x86_64-linux` 판이 있음 |
| 그 밖의 gem(`bcrypt`, `bootsnap` 등) | 빌드 단계의 `build-essential`로 컴파일, 빌드됨 | 같음, 빌드됨 |
| 시스템 라이브러리 | `Dockerfile`의 `apt`(`libjemalloc2`, `sqlite3`, `libyaml-dev` 등. `libvips`는 이미지 변환을 쓰지 않아 제거함)가 아키텍처와 무관, jemalloc 경로는 `uname -m`으로 맞춤 | 같음 |
| Traccar 이미지 | `arm64` 매니페스트 있음 | `amd64` 매니페스트 있음 |
| kamal-proxy 이미지 | `arm64` 있음 | `amd64` 있음 |
| `deploy.yml` | `builder.arch: arm64`로 바꿔야 함 | 지금 값(`amd64`) 그대로 |

- **새로 설치해야 할 라이브러리는 없다.** 이미지가 모든 의존성을 담고 서버에는 Docker만 있으면 된다. 서버에 Ruby, 시스템 라이브러리를 깔 일이 없다.
- **진짜 비용은 빌드 속도다.** 빌드하는 PC와 서버의 아키텍처가 다르면 에뮬레이션(QEMU)이라 느리다. 이 Mac(ARM)에서 amd64 빌드는 성공했지만 `apt` 단계만 약 50초가 걸렸고 전체는 수 분이 걸렸다(정확히 재지 않았다). `Dockerfile`이 QEMU 버그 때문에 `bootsnap`을 `-j 1`로 돌리는 우회까지 갖고 있다. **개발 PC가 ARM Mac이면 ARM 서버, x86 PC나 CI라면 x86 서버**가 빠르다.
- **미리 빌드된 판이 없는 gem이 나중에 추가되면** 소스에서 컴파일한다. 빌드 이미지에 컴파일러가 이미 있어 문제는 없지만 시간이 늘 수 있다.
- 개발 PC(ARM Mac)와 서버가 같은 아키텍처면 `sqlite3` 같은 네이티브 확장이 개발과 운영에서 같은 방식으로 돈다는 부수 이익이 있다.
- 확인하지 못함: 실제 Graviton2 서버와 Intel 서버에서의 성능 차이, amd64 `traccar` 컨테이너 실행(매니페스트만 확인), `t3a`(AMD)에서의 실행.

### 승격 기준과 `t4g.micro`로 운영할 때의 주의

`t4g.small`로 올리는 **제안 기준**(경험칙이며 실측 근거는 없다):
- 평상시(배포가 아닐 때)에도 스왑 사용량이 계속 늘어 약 500MB를 넘는다(`free -m`).
- `vmstat 1`에서 평상시에도 `si`/`so`(스왑 입출력)가 지속적으로 0이 아니다.
- 배포가 헬스체크 시간 초과로 되돌려진다(`bin/kamal deploy` 실패 로그).
- `dmesg | grep -i oom`에 한 번이라도 기록된다(특히 Traccar가 죽었다면 그동안 위치를 못 받은 것이다).
- CloudWatch `CPUCreditBalance`가 계속 바닥이거나 `CPUSurplusCreditBalance`가 쌓인다.

운영할 때 주의:
- **배포 시간 초과.** Kamal은 새 컨테이너가 헬스체크를 통과하기까지 기본 30초(`deploy_timeout`)만 기다린다. 메모리가 빠듯하면 부팅이 느려져 이 시간을 넘길 수 있다. 첫 배포에서 소요 시간을 보고 `deploy.yml`에 `deploy_timeout`을 늘릴지 정한다(아직 바꾸지 않았다).
- **배포 중에는 위치 수신이 위험하다.** 메모리 압박으로 Traccar가 죽거나 느려지면 그동안의 위치가 앱 큐에 쌓였다가 한꺼번에 도착한다. 운행이 없는 시간에 배포한다.
- **첫날 측정.** 서버를 올린 직후 평상시와 배포 한 번의 `free -m`, `vmstat`, `docker stats`를 남겨 두면 이 문서의 가정(OS·Docker 약 300 MiB)을 실측으로 바꿀 수 있다.

### 추천 구성

| 항목 | 추천 | 이유와 대안 |
|---|---|---|
| 리전 | **서울(`ap-northeast-2`)** | 사용자와 버스 기사가 한국에 있어 지연이 가장 짧다 |
| 인스턴스 | **`t4g.micro`** (2 vCPU, 1GiB, ARM Graviton) | **결정.** 가장 싸다($7.59/월). 메모리 1GiB라 평상시는 겨우 들어가고 배포 중에는 스왑에 의존한다(위 "1GB로 되는가", "스왑을 쓰면"). 모자라면 `t4g.small`(2GiB, $15.18)로 올린다. 올리는 기준은 아래 "승격 기준" |
| 아키텍처 | **arm64**(`t4g`). `deploy.yml`의 `builder.arch`를 `arm64`로 **바꿨다** | 확인함: Traccar 이미지는 amd64·arm64 둘 다 있고(매니페스트), Rails 이미지는 arm64로 빌드·실행된다(이 Mac에서), `Gemfile.lock`에 `aarch64-linux`가 있다. 개발 PC가 ARM Mac이면 네이티브로 빌드되어 빠르다. **개발 PC가 x86이면** arm64 빌드가 에뮬레이션이라 느리므로 그 경우에는 `t3.small`+`amd64`가 낫다 |
| OS | Ubuntu 24.04 LTS (Canonical 공식 AMI) | `deployment.md`의 절차가 Ubuntu 기준 |
| 디스크 | **gp3 20GB**, 암호화 켬 | SQLite, Traccar H2, 백업, Docker 이미지가 한 디스크. gp3가 gp2보다 싸고 기본 성능이 충분하다 |
| 스냅샷 | **AWS Data Lifecycle Manager로 일 1회, 7개 보관** | 디스크 장애·서버 재생성 대비. 앞서 문서에 적은 "같은 디스크의 백업만으로는 부족"을 메운다. 스냅샷은 전원이 켜진 때 찍어도 파일 단위로는 일관되지 않을 수 있어 **`bin/backup-storage` 백업과 함께** 쓴다 |
| 스왑 | **2GB 스왑 파일**(루트 디스크 안, 월 약 $0.18) | Ubuntu AMI는 스왑이 없다. RAM(1GiB)의 2배다. 배포 중 겹침(새 Rails 컨테이너 약 256 MiB + 부팅 순간 증가)과 Traccar의 유휴 메모리를 흡수하고, 더 커도 쓰는 양은 같아 비용은 디스크 몇 센트뿐이다. 2GB는 "적당한 크기"에 대한 판단이며 실측 근거는 없다. `swappiness`는 기본값(60)으로 두고 관찰한다 |
| 고정 IP | Elastic IP 1개 | 4장 결정 |
| 보안 그룹 | 22(**관리자 IP만**), 80, 443, **5055(임시)** 인바운드. 8082는 열지 않는다 | 80은 Let's Encrypt 발급에 필요하다. **5055는 첫 배포의 평문 위치 수신용 임시 규칙이고 HTTPS 전환(`docs/traccar-accessory.md`) 후 닫는다.** 기사 휴대폰은 이동통신망이라 출발 IP를 특정할 수 없어 443과 5055는 전체에 열어야 한다. 관리자 IP가 바뀌면 22 규칙을 고쳐야 한다 |
| 메타데이터 | **IMDSv2 필수**(`HttpTokens=required`), hop limit 1 | 컨테이너가 인스턴스 메타데이터에 닿지 못하게 한다. 앱이 AWS를 쓰지 않으므로 영향 없다 |
| IAM 인스턴스 프로파일 | 없음 | 앱이 AWS API를 부르지 않는다. 나중에 백업을 S3로 보내면 그때 최소 권한으로 추가 |
| 종료 보호 | 켠다 | 실수로 `terminate`하면 EBS와 데이터가 같이 사라진다. 중지(stop)와 종료(terminate)를 구분한다 |
| 종료 동작 | `stop`(기본값) | OS에서 `shutdown`해도 종료가 아니라 중지가 된다 |
| 태그 | `Name=where-is-my-bus` | Discord Lambda가 이름으로 찾는다 |
| 시간대 | 서버를 `Asia/Seoul`로 | 백업 cron 시각이 한국 시각이 된다(스케줄러는 별도 시간대를 쓴다) |
| 도커 로그 | `daemon.json`에 `max-size 10m`, `max-file 3` | 컨테이너 로그가 디스크를 채우지 않게 한다. Kamal 기본 설정과의 중복 여부는 확인하지 못했다 |

### 인스턴스 비교와 가격

**출처**: AWS 공개 가격표(서울 `ap-northeast-2`, Linux, 온디맨드, 공유 테넌시)를 직접 내려받아 계산했다. 인스턴스·디스크·스냅샷은 2026-10-29 공시, 공인 IPv4는 2026-10-16 공시 값이다. 금액은 USD, 한 달을 730시간으로 계산했다. 데이터 전송 요금, 세금, 환율은 넣지 않았다(위치 데이터는 작아 전송 요금은 적을 것으로 보지만 계산하지 않았다).

| 인스턴스 | vCPU / 메모리 | CPU | 시간당 | 월 730h | 비고 |
|---|---|---|---|---|---|
| **`t4g.micro`** | 2 / 1GiB | ARM | **$0.0104** | **$7.59** | **결정**(스왑 2GB와 함께, 위험은 "1GB로 되는가"와 "승격 기준") |
| `t4g.small` | 2 / 2GiB | ARM | $0.0208 | $15.18 | `t4g.micro`로 모자랄 때 올릴 후보 |
| `t3a.small` | 2 / 2GiB | AMD x86 | $0.0234 | $17.08 | x86 중 가장 쌈. `t3.small`보다 10% 싸다 |
| `t3.small` | 2 / 2GiB | Intel x86 | $0.0260 | $18.98 | `builder.arch: amd64` 유지. `t4g.small`보다 25% 비쌈 |
| `t4g.medium` | 2 / 4GiB | ARM | $0.0416 | $30.37 | 여유가 필요할 때. 메모리가 모자라 올릴 후보 |
| `t3.medium` | 2 / 4GiB | Intel x86 | $0.0520 | $37.96 | |

추가 비용: **gp3 20GB $1.82/월**(GB당 $0.0912), **Elastic IP $3.65/월**(시간당 $0.005를 24시간), 스냅샷은 저장된 데이터 GB당 $0.05/월(증분이라 최대 약 $1로 봤다, 추정).

**월 비용 (인스턴스 + 공인 IP, 디스크·스냅샷 제외)**. 각 칸은 *자동 할당 IP / Elastic IP*. 자동 IP는 켜진 시간만, Elastic IP는 24시간 나간다.

| | 24시간 켜 둠 | 하루 18시간 | 하루 12시간 |
|---|---|---|---|
| `t4g.small` | $18.83 / $18.83 | $14.13 / $15.04 | $9.42 / $11.24 |
| `t3a.small` | $20.73 / $20.73 | $15.55 / $16.46 | $10.37 / $12.19 |
| `t3.small` | $22.63 / $22.63 | $16.97 / $17.88 | $11.31 / $13.14 |
| `t4g.medium` | $34.02 / $34.02 | $25.51 / $26.43 | $17.01 / $18.83 |

**전체 월 합계 — 결정한 `t4g.micro` + Elastic IP + gp3 20GB(스왑 파일 포함) + 스냅샷 최대 $1: 24시간 약 $14.1, 18시간 약 $12.2, 12시간 약 $10.3.**

**비교용 합계 예시** (`t4g.small` + Elastic IP + gp3 20GB + 스냅샷 최대 $1): 24시간 약 **$21.7**, 18시간 약 **$17.9**, 12시간 약 **$14.1**. 같은 조건의 `t3.small`은 약 $25.5 / $20.7 / $16.0, `t4g.medium`은 약 $36.8 / $29.3 / $21.7.

해석:
- **껐다 켜는 절감은 크지 않다.** `t4g.small`에서 24시간 → 12시간은 컴퓨팅 $7.59/월을 줄인다. Elastic IP를 쓰면 그중 약 $1.83(12시간 기준)을 IPv4가 도로 가져가서 순절감은 약 $5.8이다. 운영·장애 위험(꺼진 동안의 위치 누락, 켠 직후 몰려 오는 위치)에 비해 이익이 작은지 따져 볼 만하다.
- **아키텍처 선택이 `t3.small` 대비 월 약 $3.8(24시간)을 가른다.** ARM으로 가는 비용은 `builder.arch` 변경과 개발 PC가 x86일 때의 느린 빌드뿐이다(앞 표 "아키텍처").
- **`t4g.medium`은 메모리를 2배로 사지만 가격도 2배**($15.19 더). Traccar의 힙에 상한이 없어(위 메모리 설명) 불안하면 올리고, 우선은 `t4g.small`로 시작해 `docker stats`로 본다.
- 인스턴스 크기를 바꾸는 것은 서버를 한 번 껐다 켜는 일(중지 → 유형 변경 → 시작)이라 처음 고른 크기가 틀려도 비용이 작다. Elastic IP를 쓰면 IP도 유지된다.

**이 가격표에 없는 것(확인하지 못함)**: 버스트형(T) 인스턴스의 **Unlimited 모드 초과 CPU 요금**(Linux `t3`/`t4g`의 기본 모드는 Unlimited로 알고 있다. 기준 성능을 오래 넘기면 추가 요금이 붙는다). 이 서비스는 유휴 CPU가 한 자릿수 %라 해당 없을 것으로 보지만 실제로는 CloudWatch의 `CPUSurplusCreditBalance`와 청구서로 첫 달에 확인한다. 예약 인스턴스·Savings Plan 가격도 넣지 않았다(껐다 켜는 서버에는 맞지 않는다).

### 접속 사용자

Ubuntu AMI는 root SSH를 막고 `ubuntu` 사용자로 접속한다. `deploy.yml`의 `ssh.user`를 `ubuntu`로 바꾸고(지금은 root 기본값, 주석 처리됨), 그 사용자가 `docker` 그룹에 있어야 한다. `bin/kamal setup`이 Docker를 설치할 때 sudo가 필요하다. **이 동작은 서버에서 확인하지 못했다.** 막히면 `get.docker.com` 스크립트로 직접 설치하고 `sudo usermod -aG docker ubuntu` 한다.

### 만든 직후 (`deployment.md`로 이어진다)

1. 인스턴스 생성(위 구성) → Elastic IP 연결 → Cloudflare에서 `where-is-my-bus.codefor.kr` A 레코드(프록시 끔).
2. SSH 접속 → 스왑 파일, 시간대, `daemon.json` → 호스트 디렉터리 두 곳 `/var/lib/where-is-my-bus/storage`(`chown 1000:1000`), `/var/lib/where-is-my-bus/traccar`(컨테이너가 root라 불필요), `sqlite3` 설치.
3. `deploy.yml`의 `SERVER_IP`(두 곳)과 `ssh.user`를 바꾸고(`builder.arch`는 이미 `arm64`) 스왑 파일을 만든 뒤 `bin/kamal setup` → `bin/kamal accessory details traccar` → 포워딩 확인([traccar-accessory.md](traccar-accessory.md)의 "첫 배포 후 확인").
4. 백업 cron과 DLM 스냅샷 정책을 건다. 껐다 켜는 서버는 **백업 시각에 켜져 있어야** 하므로 끄기 직전 시각에 맞춘다.

서버를 다시 만들 때는 같은 절차 뒤 백업을 복원한다. **`production.key`가 없으면 `production.yml.enc`를 열 수 없으므로** 키의 별도 보관이 복구의 전제다.

## 7. 결정 상태

| # | 항목 | 상태 |
|---|---|---|
| 1 | Traccar accessory | **적용함**(`config/deploy.yml`, [traccar-accessory.md](traccar-accessory.md)) |
| 2 | 켜고 끄는 방식 | 시간표 + 수동을 함께 쓰는 안을 추천(3장). **운행 시간표를 알려 주면 확정** |
| 3 | IP | **Elastic IP로 시작**, 한 달 운영 후 재검토(4장) |
| 4 | Discord 권한 | **운영자만, 길드·역할로 제한**(2장 권한). 허용 역할 구성은 아래 |
| 5 | 운행 중 `stop` 처리 | 대기: Lambda가 앱에 묻는 방식(내부 엔드포인트 필요)과 사람이 확인하는 방식 중 선택 |
| 6 | AWS 계정 소유자, IAM 관리자 | 대기 |
| 7 | Lambda 런타임 | 대기: Node.js(Ed25519 내장) 또는 Python + 레이어 |
| 8 | EC2 구성 | **결정: 서울 `t4g.micro`(arm64, 1GiB) + 스왑 2GB + gp3 20GB + Elastic IP + 일 1회 스냅샷**(6장). `deploy.yml`의 `builder.arch`는 `arm64`로 바꿨다. 올리는 기준은 "승격 기준" |
| 9 | Traccar 위치 수신 HTTPS | **보류, 필수 후속**(2026-11-01). 첫 배포는 동작 확인을 위해 평문 5055(`http://where-is-my-bus.codefor.kr:5055`)로 한다. 전환 방식은 서브도메인 `traccar-where-is-my-bus.codefor.kr` + nginx로 정했고 체크리스트는 [traccar-accessory.md](traccar-accessory.md)의 "HTTPS 전환 체크리스트". 평문의 위험과 앱 허용 목록은 [deployment.md](deployment.md) |

권한에서 정할 것: 허용 역할을 하나로 할지(운영자), 둘로 할지(조회 / 변경). 처음엔 하나를 추천한다.

## 확인한 것과 하지 못한 것

- 확인함(측정): 운영 이미지 Rails 컨테이너 메모리 약 200→256 MiB(arm64, 로컬 도커), Traccar 컨테이너 약 266 MiB(유휴 3일, 기기 없음), Traccar 이미지의 amd64·arm64 지원, `Gemfile.lock`의 `aarch64-linux`, 운영 이미지 arm64 빌드·실행.
- 확인함: 참고한 Slack 구현의 코드·문서 내용, 그 구현에 서버 생성 자동화가 없음, `codefor.kr` NS가 Cloudflare, `where-is-my-bus.codefor.kr` 레코드 아직 없음(2026-10-31 조회), Kamal 2.11 소스의 `--restart unless-stopped`와 `kamal` 도커 네트워크.
- 확인함(가격): 서울 리전 인스턴스·gp3·스냅샷·공인 IPv4 단가(AWS 공개 가격표, 2026-10-29와 10-16 공시). 이 PC의 AWS 사용자는 가격 API 권한이 없어 공개 가격표 파일을 직접 받아 계산했다.
- 확인하지 못함: AWS 동작(일반 지식), 버스트형 Unlimited 초과 요금, 데이터 전송 요금, Discord Interactions의 세부(서명 헤더·응답 형식·15분 토큰은 알고 있는 내용이며 이 환경에서 호출하지 않았다), Node.js `crypto`의 Ed25519 검증, Discord용으로 고친 Lambda 코드, 서버에서의 부팅 후 자동 복귀·소요 시간, 운행 시간표, 인스턴스 크기가 실제 부하에서 충분한지(위 측정은 유휴·소량 요청), kamal-proxy와 OS·Docker의 메모리, `kamal setup`이 Ubuntu에서 Docker를 설치하는지와 `ubuntu` 사용자 동작.
- 이 조사에서 AWS는 `aws sts get-caller-identity`로 로그인 계정만 조회했다. Discord는 호출하지 않았다.
