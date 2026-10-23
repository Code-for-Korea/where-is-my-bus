class PagesController < ApplicationController
  allow_unauthenticated_access

  # 승객 첫 화면: 기다리는 정류장을 고른다. 어느 노선에도 속하지 않은 정류장은 보여줄 버스가 없으므로 뺀다.
  def index
    @stops = Stop.joins(:route_stops).distinct.ordered.includes(:routes)
  end
end
