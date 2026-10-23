# Product Requirements

### 주체
- 관리자: 데이터 관리
- 운전자: 버스의 현재 GPS 전송
- 승객: 선택한 노선에 해당하는 버스의 현재 위치 조회

### 객체
- 정류장: Traccar의 Geofence에 대응
- 버스: Traccar의 Device에 대응. 운전자가 아니라 차량을 가리킴
- 노선: Traccar의 Device Group에 대응

### MVP 기능
1. 관리자는 정류장을 등록할 수 있다.
  - 정류장은 Traccar의 Geofence와 대응되며, 정류장 등록 시 Traccar 서버에 Geofence를 자동생성한다.
  - 버스가 정류장 도착/출발은 [Geofence Entered/Geofence Exited 이벤트](https://www.traccar.org/events/#:~:text=a%20calendar.-,Event%20Types,-Type)로 감지한다.
2. 운전자는 버스의 현재 GPS를 전송할 수 있다. 
3. 승객은 특정 정류장을 기준으로 본인이 기다리는 노선에 해당하는 버스가 어느 정류장에 있는지 조회할 수 있다.