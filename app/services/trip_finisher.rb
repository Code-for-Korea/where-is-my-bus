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

    trip.finish!

    cleared = TraccarDeviceGroup.clear(bus)
    if cleared.failure?
      Rails.logger.warn("[TripFinisher] bus #{bus.id} trip #{trip.id} ended but Traccar group was not cleared: #{cleared.error}")
      return Result.new(trip: trip, warning: :group_clear_failed)
    end

    Result.new(trip: trip)
  end
end
