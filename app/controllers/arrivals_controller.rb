class ArrivalsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_stop_and_route

  # 정류장 + 노선 → 이 노선을 운행 중인 버스들의 현재 위치.
  def show
    @statuses = RouteBusStatuses.call(route: @route, stop: @stop)
    @route_stops = @route.route_stops.includes(:stop)
  end

  # 화면이 주기적으로 갱신하는 부분(레이아웃 없이 본문 조각만).
  def buses
    @statuses = RouteBusStatuses.call(route: @route, stop: @stop)
    @route_stops = @route.route_stops.includes(:stop)

    render partial: "arrivals/buses", locals: { statuses: @statuses, route_stops: @route_stops, stop: @stop }
  end

  private

  # 정류장이 그 노선에 속하지 않으면 보여줄 것이 없으므로 404.
  def set_stop_and_route
    @stop = Stop.find(params[:stop_id])
    @route = @stop.routes.find(params[:route_id])
  end
end
