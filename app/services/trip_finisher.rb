# 운전자가 운행을 종료한다: 운행(Trip)을 닫고 버스의 Traccar device를 group에서 뺀다.
# 운행 종료는 Traccar 장애와 무관하게 항상 성공한다 — 그룹 해제가 실패하면 경고만 남긴다.
# 남은 group 소속은 다음 운행 시작 때 덮어써지고, 그 사이 이벤트는 진행 중인 운행이 없어 무시된다.
#
# 진행 중인 운행이 없어도 오류가 아니다(멱등) — 종료 응답이 유실돼 재시도하는 경우를 받아 준다.
class TripFinisher
  Result = Struct.new(:trip, :warning, keyword_init: true)

  def self.call(bus)
    trip = bus.active_trip
    return Result.new unless trip

    close_trip(trip)

    cleared = TraccarDeviceGroup.clear(bus)
    if cleared.failure?
      Rails.logger.warn("[TripFinisher] bus #{bus.id} trip #{trip.id} ended but Traccar group was not cleared: #{cleared.error}")
      return Result.new(trip: trip, warning: :group_clear_failed)
    end

    Result.new(trip: trip)
  end

  # 운행이 끝나면 버스는 어느 정류장에도 없다. 마지막 정류장의 이탈 이벤트가 종료보다 늦게 도착하면
  # 진행 중인 운행이 없어 무시되므로(StopVisitRecorder), 열린 방문 기록은 종료 시각으로 닫아 둔다.
  def self.close_trip(trip)
    Trip.transaction do
      trip.finish!
      trip.stop_visits.open.update_all(exited_at: trip.ended_at, updated_at: Time.current)
    end
  end
  private_class_method :close_trip
end
