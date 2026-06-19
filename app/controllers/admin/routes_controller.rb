module Admin
  class RoutesController < BaseController
    before_action :set_route, only: %i[show edit update destroy]

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
      @route.destroy
      redirect_to admin_routes_path, notice: "노선이 삭제되었습니다.", status: :see_other
    end

    private

    def set_route
      @route = Route.find(params[:id])
    end

    def route_params
      params.require(:route).permit(:area_id, :bus_id, :name, :headway_minutes, :position)
    end
  end
end
