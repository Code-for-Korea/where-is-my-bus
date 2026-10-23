class PagesController < ApplicationController
  allow_unauthenticated_access
  layout "service"
  before_action :load_selector_data

  # 승객 첫 화면. 버튼을 누르면 정류장·노선 선택 바텀시트가 열린다.
  def index
  end

  def about
    @routes = @selector_routes
  end
end
