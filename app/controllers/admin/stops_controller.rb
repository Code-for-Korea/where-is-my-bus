module Admin
  class StopsController < BaseController
    before_action :set_stop, only: %i[show edit update destroy sync_geofence]

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
        attempt_geofence_sync
        redirect_to admin_stops_path(route_id: @stop.route_id), notice: "정류장이 등록되었습니다."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @stop.update(stop_params)
        attempt_geofence_sync
        redirect_to admin_stops_path(route_id: @stop.route_id), notice: "정류장이 수정되었습니다."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      route_id = @stop.route_id
      # Traccar geofence 삭제가 실패해도 로깅만 하고 Stop 삭제는 계속 진행한다.
      result = TraccarGeofenceSync.destroy(@stop)
      Rails.logger.error("[Admin::StopsController] geofence 삭제 실패, stop=#{@stop.id}: #{result.error}") if result.failure?
      @stop.destroy
      redirect_to admin_stops_path(route_id: route_id), notice: "정류장이 삭제되었습니다.", status: :see_other
    end

    def sync_geofence
      result = TraccarGeofenceSync.call(@stop)
      if result.failure?
        flash[:alert] = result.error
      else
        flash[:notice] = "geofence 동기화에 성공했습니다."
      end
      redirect_to admin_stop_path(@stop)
    end

    private

    def set_stop
      @stop = Stop.find(params[:id])
    end

    def stop_params
      params.require(:stop).permit(:route_id, :name, :sequence, :lat, :lng, :avg_travel_seconds, :name_en)
    end

    def attempt_geofence_sync
      result = TraccarGeofenceSync.call(@stop)
      flash[:alert] = result.error if result.failure?
    end
  end
end
