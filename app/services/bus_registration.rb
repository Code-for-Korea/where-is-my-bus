# 버스 생성/수정/삭제 + Traccar device 동기화.
class BusRegistration < TraccarRegistration
  manages Bus, with: TraccarDeviceSync
end
