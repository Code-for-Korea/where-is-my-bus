module Admin
  class StopsController < BaseController
    before_action :set_stop, only: %i[show edit update destroy sync_geofence]

    def index
      @stops = Stop.ordered.includes(:routes)
    end

    def show
    end

    def new
      @stop = Stop.new
    end

    def create
      result = StopRegistration.create(stop_params)
      return redirect_to admin_stop_path(result.record), notice: "정류장이 등록되었습니다." if result.success?

      @stop = result.record
      render_failure :new, result
    end

    def edit
    end

    def update
      result = StopRegistration.update(@stop, stop_params)
      return redirect_to admin_stop_path(@stop), notice: "정류장이 수정되었습니다." if result.success?

      render_failure :edit, result
    end

    def destroy
      result = StopRegistration.destroy(@stop)
      if result.success?
        redirect_to admin_stops_path, notice: "정류장이 삭제되었습니다.", status: :see_other
      else
        redirect_to admin_stop_path(@stop), alert: "삭제할 수 없습니다: #{result.error}", status: :see_other
      end
    end

    # 드리프트(Traccar 콘솔에서 geofence를 수동 삭제 등) 복구용 재동기화.
    def sync_geofence
      result = StopRegistration.update(@stop, {})
      if result.success?
        redirect_to admin_stop_path(@stop), notice: "정류장 영역 동기화에 성공했습니다."
      else
        redirect_to admin_stop_path(@stop), alert: result.error
      end
    end

    private

    def set_stop
      @stop = Stop.find(params[:id])
    end

    def stop_params
      params.require(:stop).permit(:name, :lat, :lng)
    end
  end
end
