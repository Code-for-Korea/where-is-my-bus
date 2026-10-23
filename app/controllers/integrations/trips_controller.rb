module Integrations
  # 운전자 앱의 운행 시작·종료. 버스는 deviceId(= buses.traccar_unique_id)로 식별한다.
  # 노선은 앱이 보내지 않는다 — 관리자가 차량에 배정한 노선으로 운행한다.
  # ponytail: deviceId가 사실상 비밀번호다 — 기기별 토큰 발급은 후속 과제 (docs/future-improvements.md 2번).
  class TripsController < ActionController::API
    before_action :set_bus

    # POST /integrations/traccar/trips/start { deviceId }
    def start
      result = TripStarter.call(bus: @bus)
      case result.status
      when :started, :already_active
        render json: { trip: TripSerializer.call(result.trip) }
      when :no_route
        render json: { error: "no_route_assigned" }, status: :unprocessable_entity
      end
    end

    # POST /integrations/traccar/trips/end { deviceId }
    # 진행 중인 운행이 없어도 200 — 종료 응답이 유실돼 재시도하는 경우를 받아 준다.
    def finish
      result = TripFinisher.call(@bus)

      render json: { ended: result.trip.present? }
    end

    private

    def set_bus
      @bus = Bus.find_by(traccar_unique_id: params[:deviceId].to_s)
      render json: { error: "unknown_device" }, status: :not_found if @bus.nil?
    end
  end
end
