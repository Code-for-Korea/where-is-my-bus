module Admin
  # 노선에 차량을 배정하거나 푼다. 차량은 노선 하나에만 배정되므로, 다른 노선의 차량을 배정하면 그 노선에서 옮겨 온다.
  # 배정이 바뀌면 Traccar 기기가 그 노선의 group으로 옮겨진다 (BusRegistration, 실패하면 함께 롤백).
  class BusAssignmentsController < BaseController
    before_action :set_route

    def create
      bus = Bus.find_by(id: params[:bus_id])
      return redirect_to admin_route_path(@route), alert: "배정할 차량을 선택해 주세요." if bus.nil?

      result = BusRegistration.update(bus, route_id: @route.id)
      if result.success?
        redirect_to admin_route_path(@route), notice: "#{bus.license_plate} 차량을 #{@route.name}에 배정했습니다."
      else
        redirect_to admin_route_path(@route), alert: "배정할 수 없습니다: #{result.error}"
      end
    end

    def destroy
      bus = @route.buses.find(params[:id])
      result = BusRegistration.update(bus, route_id: nil)
      if result.success?
        redirect_to admin_route_path(@route), notice: "#{bus.license_plate} 차량의 배정을 풀었습니다.", status: :see_other
      else
        redirect_to admin_route_path(@route), alert: "배정을 풀 수 없습니다: #{result.error}", status: :see_other
      end
    end

    private

    def set_route
      @route = Route.find(params[:route_id])
    end
  end
end
