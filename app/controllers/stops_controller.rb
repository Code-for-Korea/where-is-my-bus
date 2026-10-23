class StopsController < ApplicationController
  allow_unauthenticated_access

  # 정류장에 서는 노선이 하나뿐이면 노선 선택을 건너뛰고 바로 버스 위치로 보낸다.
  def show
    @stop = Stop.find(params[:id])
    @routes = @stop.routes.ordered.to_a

    return redirect_to stop_route_arrivals_path(@stop, @routes.first) if @routes.one?

    @active_trip_counts = Trip.active.where(route_id: @routes.map(&:id)).group(:route_id).count
  end
end
