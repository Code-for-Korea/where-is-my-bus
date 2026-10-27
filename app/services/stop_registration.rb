# 정류장 생성/수정/삭제 + Traccar geofence 동기화.
class StopRegistration < TraccarRegistration
  manages Stop, with: TraccarGeofenceSync
end
