# 운전자가 운행을 종료한다: 운행(Trip)을 닫는다. Traccar는 부르지 않으므로 Traccar 장애와 무관하게 항상 성공한다.
# 진행 중인 운행이 없어도 오류가 아니다(멱등) — 종료 응답이 유실돼 재시도하는 경우를 받아 준다.
class TripFinisher
  Result = Struct.new(:trip, keyword_init: true)

  def self.call(bus)
    trip = bus.active_trip
    return Result.new unless trip

    close_trip(trip)
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
