class RoutesController < ApplicationController
  # 시민용 노선 화면 (실시간 위치 / 정류장 목록 / 좋아요). 로그인 없이 공개.
  allow_unauthenticated_access
  layout "service"

  before_action :set_route

  def show
    @stops = @route.stops.to_a
    @liked = liked?(@route)

    # ⚠️ 버스 위치/도착예정은 아직 미구현 — 운전자 앱(GPS) 연동 전까지 예시 값.
    @stops_before  = 1
    @eta_minutes   = 20
    @current_index = @stops.size >= 3 ? 2 : 0
    @next_stop     = @stops[[@current_index + @stops_before, @stops.size - 1].min] if @stops.any?
  end

  def stops
    @stops = @route.stops.to_a
    @liked = liked?(@route)
    @current_index = @stops.size >= 3 ? 2 : 0
  end

  # 좋아요 토글 (세션 기반, 1인 1회)
  def like
    ids = (session[:liked_route_ids] ||= [])
    if ids.include?(@route.id)
      Route.where(id: @route.id).update_all("likes_count = likes_count - 1")
      ids.delete(@route.id)
    else
      Route.where(id: @route.id).update_all("likes_count = likes_count + 1")
      ids << @route.id
    end
    redirect_back fallback_location: route_path(@route)
  end

  private

  def set_route
    @route = Route.includes(:stops, area: :region).find(params[:id])
  end

  def liked?(route)
    session[:liked_route_ids]&.include?(route.id)
  end
end
