module Admin
  class RoutesController < BaseController
    before_action :set_route, only: %i[show edit update destroy sync_group]

    def index
      @routes = Route.includes(area: :region).all
      @routes = @routes.where(area_id: params[:area_id]) if params[:area_id].present?
    end

    def show
    end

    def new
      @route = Route.new(area_id: params[:area_id])
    end

    def create
      @route = Route.new(route_params)
      if @route.save
        attempt_group_sync
        redirect_to admin_route_path(@route), notice: "노선이 등록되었습니다."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @route.update(route_params)
        redirect_to admin_route_path(@route), notice: "노선이 수정되었습니다."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      # Traccar group 삭제가 실패해도 로깅만 하고 Route 삭제는 계속 진행한다.
      # group이 고아로 남는 것보다 관리자의 삭제 의도를 막지 않는 게 우선.
      result = TraccarGroupSync.destroy(@route)
      Rails.logger.error("[Admin::RoutesController] group 삭제 실패, route=#{@route.id}: #{result.error}") if result.failure?
      @route.destroy
      redirect_to admin_routes_path, notice: "노선이 삭제되었습니다.", status: :see_other
    end

    def sync_group
      result = TraccarGroupSync.call(@route)
      if result.failure?
        flash[:alert] = result.error
      else
        flash[:notice] = "group 동기화에 성공했습니다."
      end
      redirect_to admin_route_path(@route)
    end

    private

    def set_route
      @route = Route.find(params[:id])
    end

    def route_params
      params.require(:route).permit(:area_id, :name, :headway_minutes, :position)
    end

    def attempt_group_sync
      result = TraccarGroupSync.call(@route)
      flash[:alert] = result.error if result.failure?
    end
  end
end
