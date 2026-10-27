module Admin
  class RoutesController < BaseController
    before_action :set_route, only: %i[show edit update destroy sync_group]

    def index
      @routes = Route.ordered.includes(:route_stops)
    end

    def show
      @route_stops = @route.route_stops.includes(:stop)
      @candidate_stops = Stop.where.not(id: @route.stop_ids).ordered
      @next_sequence = (@route_stops.map(&:sequence).max || 0) + 1
      @buses = @route.buses.ordered.includes(:active_trip)
      @candidate_buses = Bus.where.not(route_id: @route.id).or(Bus.where(route_id: nil)).ordered.includes(:route)
    end

    def new
      @route = Route.new
    end

    def create
      result = RouteRegistration.create(route_params)
      return redirect_to admin_route_path(result.record), notice: "노선이 등록되었습니다." if result.success?

      @route = result.record
      render_failure :new, result
    end

    def edit
    end

    def update
      result = RouteRegistration.update(@route, route_params)
      return redirect_to admin_route_path(@route), notice: "노선이 수정되었습니다." if result.success?

      render_failure :edit, result
    end

    def destroy
      result = RouteRegistration.destroy(@route)
      if result.success?
        redirect_to admin_routes_path, notice: "노선이 삭제되었습니다.", status: :see_other
      else
        redirect_to admin_route_path(@route), alert: "삭제할 수 없습니다: #{result.error}", status: :see_other
      end
    end

    # 완전 롤백 정책 하에서는 동기화 실패한 채로 저장된 노선이 생기지 않으므로, 이 액션은
    # Traccar 콘솔에서 group을 수동으로 지우는 등의 드리프트가 생겼을 때 다시 맞추는 "재동기화" 용도다.
    def sync_group
      result = RouteRegistration.update(@route, {})
      if result.success?
        redirect_to admin_route_path(@route), notice: "Traccar 노선 동기화에 성공했습니다."
      else
        redirect_to admin_route_path(@route), alert: result.error
      end
    end

    private

    def set_route
      @route = Route.find(params[:id])
    end

    def route_params
      params.require(:route).permit(:name)
    end
  end
end
