module Admin
  class StopsController < BaseController
    before_action :set_stop, only: %i[show edit update destroy]

    def index
      @stops = Stop.includes(route: { area: :region }).all
      @stops = @stops.where(route_id: params[:route_id]) if params[:route_id].present?
    end

    def show
    end

    def new
      @stop = Stop.new(route_id: params[:route_id])
    end

    def create
      @stop = Stop.new(stop_params)
      if @stop.save
        redirect_to admin_stops_path(route_id: @stop.route_id), notice: "정류장이 등록되었습니다."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @stop.update(stop_params)
        redirect_to admin_stops_path(route_id: @stop.route_id), notice: "정류장이 수정되었습니다."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      route_id = @stop.route_id
      @stop.destroy
      redirect_to admin_stops_path(route_id: route_id), notice: "정류장이 삭제되었습니다.", status: :see_other
    end

    private

    def set_stop
      @stop = Stop.find(params[:id])
    end

    def stop_params
      params.require(:stop).permit(:route_id, :name, :position, :latitude, :longitude)
    end
  end
end
