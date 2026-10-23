module Integrations
  # 운전자 앱의 운행 시작·종료. 버스는 deviceId(= buses.traccar_unique_id)로 식별한다.
  # ponytail: deviceId가 사실상 비밀번호다 — 기기별 토큰 발급은 후속 과제 (docs/future-improvements.md 2번).
  class TripsController < ActionController::API
    before_action :set_bus

    # POST /integrations/traccar/trips/start { deviceId, routeId }
    def start
      route = Route.find_by(id: params[:routeId])
      return render json: { error: "unknown_route" }, status: :not_found if route.nil?

      result = TripStarter.call(bus: @bus, route: route)
      case result.status
      when :started, :already_active
        render json: { trip: TripSerializer.call(result.trip) }
      when :conflict
        render json: { error: "trip_already_active", trip: TripSerializer.call(result.trip) }, status: :conflict
      when :traccar_failed
        render json: { error: "traccar_unavailable", message: result.error }, status: :bad_gateway
      end
    end

    # POST /integrations/traccar/trips/end { deviceId }
    # 진행 중인 운행이 없어도 200 — 종료 응답이 유실돼 재시도하는 경우를 받아 준다.
    def finish
      result = TripFinisher.call(@bus)

      render json: { ended: result.trip.present?, warning: result.warning }.compact
    end

    private

    def set_bus
      @bus = Bus.find_by(traccar_unique_id: params[:deviceId].to_s)
      render json: { error: "unknown_device" }, status: :not_found if @bus.nil?
    end
  end
end
