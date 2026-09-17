module Admin
  class RouteBusesController < BaseController
    def create
      route_bus = RouteBus.new(route_id: params[:route_id], bus_id: params[:bus_id])
      if route_bus.save
        result = TraccarGroupMembership.add(route_bus)
        flash[:alert] = result.error if result.failure?
      end
      redirect_to admin_route_path(route_bus.route)
    end

    def destroy
      route_bus = RouteBus.find(params[:id])
      # Traccar group 연결 해제가 실패해도 로깅만 하고 배차 해제는 계속 진행한다.
      # Route 삭제와 같은 판단 기준.
      result = TraccarGroupMembership.remove(route_bus)
      Rails.logger.error("[Admin::RouteBusesController] group 해제 실패, route_bus=#{route_bus.id}: #{result.error}") if result.failure?
      route_bus.destroy
      redirect_to admin_route_path(route_bus.route), status: :see_other
    end
  end
end
