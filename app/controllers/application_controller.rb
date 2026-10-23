class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  # 버스 선택 바텀시트(shared/_bus_selector_sheet)가 쓰는 정류장·노선 목록. 승객 화면에서 공통으로 쓴다.
  # 노선에 속하지 않은 정류장은 보여줄 버스가 없으므로 뺀다.
  def load_selector_data
    @selector_stops = Stop.joins(:route_stops).distinct.ordered.includes(:routes)
    @selector_routes = Route.ordered.includes(:route_stops)
  end
end
