# 운전자가 운행을 시작한다: 차량에 배정된 노선으로 운행(Trip)을 만든다.
# 노선은 운전자가 고르지 않는다 — 관리자가 차량에 배정해 둔 노선을 쓴다. 기기가 그 노선의 Traccar group에
# 들어가는 것은 관리자가 배정할 때 이미 끝나 있으므로(BusRegistration) 여기서는 Traccar를 부르지 않는다.
#
# status:
#   :started        새 운행을 시작했다
#   :already_active 이미 운행 중이다 (앱 재시작·재시도에 대한 멱등 응답)
#   :no_route       차량에 배정된 노선이 없다
class TripStarter
  Result = Struct.new(:status, :trip, keyword_init: true)

  def self.call(bus:)
    existing = bus.active_trip
    return Result.new(status: :already_active, trip: existing) if existing
    return Result.new(status: :no_route) unless bus.route

    Result.new(status: :started, trip: bus.trips.create!(route: bus.route, started_at: Time.current))
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    # 동시에 두 요청이 시작을 시도해 다른 쪽이 먼저 운행을 만든 경우.
    existing = bus.reload.active_trip
    raise unless existing

    Result.new(status: :already_active, trip: existing)
  end
end
