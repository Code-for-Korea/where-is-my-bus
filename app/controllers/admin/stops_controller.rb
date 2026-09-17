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
      success = false

      ActiveRecord::Base.transaction do
        raise ActiveRecord::Rollback unless @stop.save

        result = TraccarGeofenceSync.call(@stop)
        if result.failure?
          @traccar_error = result.error
          raise ActiveRecord::Rollback
        end

        success = true
      end

      if success
        redirect_to admin_stops_path(route_id: @stop.route_id), notice: "정류장이 등록되었습니다."
      else
        @stop.errors.add(:base, "Traccar 연동 실패: #{@traccar_error}") if @traccar_error
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      success = false

      ActiveRecord::Base.transaction do
        raise ActiveRecord::Rollback unless @stop.update(stop_params)

        result = TraccarGeofenceSync.call(@stop)
        if result.failure?
          @traccar_error = result.error
          raise ActiveRecord::Rollback
        end

        success = true
      end

      if success
        redirect_to admin_stops_path(route_id: @stop.route_id), notice: "정류장이 수정되었습니다."
      else
        @stop.errors.add(:base, "Traccar 연동 실패: #{@traccar_error}") if @traccar_error
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      route_id = @stop.route_id
      # 정합성 정책: Traccar geofence 삭제가 성공해야만 Stop을 삭제한다.
      result = TraccarGeofenceSync.destroy(@stop)
      if result.failure?
        redirect_to admin_stop_path(@stop), alert: "Traccar 연동 실패로 삭제할 수 없습니다: #{result.error}"
        return
      end

      @stop.destroy
      redirect_to admin_stops_path(route_id: route_id), notice: "정류장이 삭제되었습니다.", status: :see_other
    end

    # 완전 롤백 정책 하에서는 동기화 실패한 채로 저장된 Stop이 생기지 않으므로, 이 액션은
    # "실패 재시도"가 아니라 드리프트가 생겼을 때 다시 맞추는 "재동기화" 용도로 남겨둔다.
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
  end
end
