# 운전자가 노선을 골라 운행을 시작한다: 운행(Trip)을 만들고 버스의 Traccar device를 그 노선 group으로 옮긴다.
# 둘은 한 트랜잭션이다 — group 이동이 실패하면 운행도 만들지 않는다
# (이벤트를 받지 못하는 채로 운행이 시작되는 것보다 안전하다).
#
# status:
#   :started        새 운행을 시작했다
#   :already_active 같은 노선으로 이미 운행 중이다 (앱 재시작·재시도에 대한 멱등 응답)
#   :conflict       다른 노선으로 이미 운행 중이다 (먼저 종료해야 한다)
#   :traccar_failed device group 이동 실패 (error에 사유)
class TripStarter
  Result = Struct.new(:status, :trip, :error, keyword_init: true)

  def self.call(bus:, route:)
    existing = bus.active_trip
    return Result.new(status: existing.route_id == route.id ? :already_active : :conflict, trip: existing) if existing

    trip = nil
    error = nil
    ActiveRecord::Base.transaction do
      trip = bus.trips.create!(route: route, started_at: Time.current)
      moved = TraccarDeviceGroup.assign(bus, route)
      if moved.failure?
        error = moved.error
        raise ActiveRecord::Rollback
      end
    end

    error ? Result.new(status: :traccar_failed, error: error) : Result.new(status: :started, trip: trip)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    # 동시에 두 요청이 시작을 시도해 다른 쪽이 먼저 운행을 만든 경우.
    existing = bus.reload.active_trip
    Result.new(status: existing&.route_id == route.id ? :already_active : :conflict, trip: existing)
  end
end
