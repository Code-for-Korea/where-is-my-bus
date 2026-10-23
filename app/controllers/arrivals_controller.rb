class ArrivalsController < ApplicationController
  allow_unauthenticated_access
  layout "service"
  before_action :set_stop_and_route
  before_action :build_presenter
  before_action :load_selector_data, only: :show

  # 정류장 + 노선 → 이 노선을 운행 중인 버스들의 현재 위치.
  def show
  end

  # 5초마다 화면이 읽어 가는 현재 상태.
  def status
    render json: @presenter.to_h
  end

  # 자세히보기 모달(Turbo Frame): 노선의 정류장 순서와 버스 위치.
  def detail
  end

  private

  # 정류장이 그 노선에 속하지 않으면 보여줄 것이 없으므로 404.
  def set_stop_and_route
    @stop = Stop.find(params[:stop_id])
    @route = @stop.routes.find(params[:route_id])
  end

  def build_presenter
    @route_stops = @route.route_stops.includes(:stop)
    @presenter = ArrivalPresenter.new(statuses: RouteBusStatuses.call(route: @route, stop: @stop),
                                      route_stops: @route_stops, stop: @stop)
  end
end
