module Admin
  class RouteBusesController < BaseController
    def create
      route_bus = RouteBus.new(route_id: params[:route_id], bus_id: params[:bus_id])
      success = false
      traccar_error = nil

      ActiveRecord::Base.transaction do
        raise ActiveRecord::Rollback unless route_bus.save

        result = TraccarGroupMembership.add(route_bus)
        if result.failure?
          traccar_error = result.error
          raise ActiveRecord::Rollback
        end

        success = true
      end

      flash[:alert] = "Traccar 연동 실패: #{traccar_error}" unless success
      redirect_to admin_route_path(route_bus.route)
    end

    def destroy
      route_bus = RouteBus.find(params[:id])
      # 정합성 정책: Traccar group 연결 해제가 성공해야만 배차를 해제(RouteBus 삭제)한다.
      result = TraccarGroupMembership.remove(route_bus)
      if result.failure?
        redirect_to admin_route_path(route_bus.route), alert: "Traccar 연동 실패로 배차를 해제할 수 없습니다: #{result.error}"
        return
      end

      route_bus.destroy
      redirect_to admin_route_path(route_bus.route), status: :see_other
    end
  end
end
