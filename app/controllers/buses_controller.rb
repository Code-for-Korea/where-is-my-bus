class BusesController < ApplicationController
  # 시민용 서비스 진입/소개/노선 선택. 로그인 없이 공개.
  allow_unauthenticated_access
  layout "service"

  def index # 스플래시
  end

  def about
    @region_count = Region.count
    @route_count  = Route.count
    @areas = Area.includes(:region).limit(10)
  end

  def select # 지역·노선 선택
    @regions = Region.all
    @areas   = Area.includes(:region).all
    @routes  = Route.includes(area: :region).all
    @region_count = Region.count
    @route_count  = Route.count
  end

  def go # 선택한 노선으로 이동
    route = Route.find_by(id: params[:route_id])
    if route
      redirect_to route_path(route)
    else
      redirect_to service_select_path, alert: "노선을 선택해주세요."
    end
  end
end
