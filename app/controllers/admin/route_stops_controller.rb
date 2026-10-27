module Admin
  # 노선에 정류장을 추가/제거한다. 정차 순서는 추가할 때 입력하고, 바꾸려면 제거 후 다시 추가한다
  # (순서 재배열은 docs/future-improvements.md 11번).
  class RouteStopsController < BaseController
    before_action :set_route

    def create
      result = RouteStopRegistration.create(route: @route, stop: Stop.find_by(id: params[:stop_id]), sequence: params[:sequence])
      if result.success?
        redirect_to admin_route_path(@route), notice: "정류장을 노선에 추가했습니다."
      else
        redirect_to admin_route_path(@route), alert: "추가할 수 없습니다: #{result.error}"
      end
    end

    def destroy
      result = RouteStopRegistration.destroy(@route.route_stops.find(params[:id]))
      if result.success?
        redirect_to admin_route_path(@route), notice: "정류장을 노선에서 제거했습니다.", status: :see_other
      else
        redirect_to admin_route_path(@route), alert: "제거할 수 없습니다: #{result.error}", status: :see_other
      end
    end

    private

    def set_route
      @route = Route.find(params[:route_id])
    end
  end
end
