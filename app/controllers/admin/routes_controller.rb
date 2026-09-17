module Admin
  class RoutesController < BaseController
    before_action :set_route, only: %i[show edit update destroy sync_group]

    def index
      @routes = Route.includes(area: :region).all
      @routes = @routes.where(area_id: params[:area_id]) if params[:area_id].present?
    end

    def show
      @candidate_buses = @route.area.buses.where.not(id: @route.buses.select(:id))
    end

    def new
      @route = Route.new(area_id: params[:area_id])
    end

    def create
      @route = Route.new(route_params)
      success = false

      ActiveRecord::Base.transaction do
        raise ActiveRecord::Rollback unless @route.save

        result = TraccarGroupSync.call(@route)
        if result.failure?
          @traccar_error = result.error
          raise ActiveRecord::Rollback
        end

        success = true
      end

      if success
        redirect_to admin_route_path(@route), notice: "노선이 등록되었습니다."
      else
        @route.errors.add(:base, "Traccar 연동 실패: #{@traccar_error}") if @traccar_error
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
      # 정합성 정책: Traccar group 삭제가 성공해야만 Route를 삭제한다.
      result = TraccarGroupSync.destroy(@route)
      if result.failure?
        redirect_to admin_route_path(@route), alert: "Traccar 연동 실패로 삭제할 수 없습니다: #{result.error}"
        return
      end

      @route.destroy
      redirect_to admin_routes_path, notice: "노선이 삭제되었습니다.", status: :see_other
    end

    # 완전 롤백 정책 하에서는 동기화 실패한 채로 저장된 Route가 생기지 않으므로, 이 액션은
    # "실패 재시도"가 아니라 Traccar 콘솔에서 수동으로 group을 지우는 등의 드리프트가 생겼을 때
    # 다시 맞추는 "재동기화" 용도로 남겨둔다.
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
  end
end
