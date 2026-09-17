class StopsController < ApplicationController
  allow_unauthenticated_access
  before_action :no_turbo_cache, only: %i[show detail]

  def show
    @stop   = Stop.find_by(id: params[:stop_id])
    @bus    = @stop&.route&.buses&.first
    @region = @bus&.region
    @area   = @bus&.area
    token = session[:like_token] ||= SecureRandom.hex(16)
    @likes_count      = @stop ? StopLike.where(stop_id: @stop.id).count : 0
    @already_liked    = @stop ? StopLike.where(stop_id: @stop.id, session_token: token)
                                        .where("created_at > ?", 1.hour.ago).exists? : false
    load_selector_regions
  end

  def detail
    @stop = Stop.find_by(id: params[:stop_id])
    return head :not_found unless @stop

    @bus    = @stop.route&.buses&.first
    @region = @bus&.region
    @area   = @bus&.area
    return render json: { error: "data error" }, status: :unprocessable_entity if @bus.nil? || @region.nil?

    @likes_count = StopLike.where(stop_id: @stop.id).count
    load_selector_regions

    all_stops = @stop.route.stops.order(:sequence).to_a

    selection = RouteBusSelector.call(@stop.route, @stop)
    bus_stop  = selection.status == :ok ? selection.progress.current_stop(@stop.route) : nil

    @route_stops = all_stops.map do |s|
      { seq: s.sequence, name: s.display_name,
        current_bus: bus_stop&.id == s.id,
        here: @stop.id == s.id }
    end
  end

  def arrival
    target_stop = Stop.find_by(id: params[:stop_id])
    return render json: { status: "no_data", eta_minutes: nil, stops_away: nil } unless target_stop

    route = target_stop.route
    return render json: { status: "no_data", eta_minutes: nil, stops_away: nil } unless route

    selection = RouteBusSelector.call(route, target_stop)
    case selection.status
    when :no_trip
      return render json: { eta_minutes: nil, stops_away: nil, bus_number: nil, status: "no_trip" }
    when :no_gps
      return render json: { status: "no_data", eta_minutes: nil, stops_away: nil, bus_number: nil }
    end

    result = selection.progress.eta_to(target_stop)
    return render json: { status: "no_data", eta_minutes: nil, stops_away: nil, bus_number: selection.bus.bus_number } unless result

    render json: result.merge(bus_number: selection.bus.bus_number)
  end

  def debug_bus
    return render json: { error: "not found" }, status: :not_found unless Rails.env.development?

    target_stop = Stop.find_by(id: params[:stop_id])
    return render json: { error: "stop not found" }, status: :not_found unless target_stop

    seq = params[:seq].to_i
    pct = params[:pct].to_f.clamp(0.0, 100.0)
    return render json: { error: "invalid seq" }, status: :bad_request if seq <= 0

    route     = target_stop.route
    all_stops = route.stops.order(:sequence).to_a

    bus_stop    = all_stops.find { |s| s.sequence == seq }
    return render json: { error: "sequence not found" }, status: :not_found unless bus_stop

    # 목표 정류장: 현재 페이지의 정류장 (params[:stop_id])
    debug_target = target_stop

    # 개발 전용 GPS 시뮬레이터: 배정된 버스가 여러 대여도 특정 버스를 지목할 개념이 없으므로
    # 첫 번째 버스에 GPS를 심는 것으로 단순 유지한다(RouteBusSelector의 "가장 가까운 버스
    # 선택" 로직은 승객 화면 표시용이라 이 디버그 도구와는 목적이 다르다).
    trip = route.buses.first.trips.where(ended_at: nil).order(started_at: :desc).first
    return render json: { error: "no active trip" }, status: :unprocessable_entity unless trip

    # pct: 0 = 정류장 위치, 0~100 = 다음 정류장 방향 보간 (상단에서 이미 clamp 처리됨)

    # GPS 위치 계산 (보간 포함)
    gps_lat, gps_lng = if pct > 0
      next_stop = all_stops.find { |s| s.sequence == seq + 1 }
      next_stop ? [
        bus_stop.lat.to_f + (next_stop.lat.to_f - bus_stop.lat.to_f) * pct / 100,
        bus_stop.lng.to_f + (next_stop.lng.to_f - bus_stop.lng.to_f) * pct / 100
      ] : [ bus_stop.lat.to_f, bus_stop.lng.to_f ]
    else
      [ bus_stop.lat.to_f, bus_stop.lng.to_f ]
    end

    gps = trip.gps_logs.order(recorded_at: :desc).first
    if gps
      gps.update!(lat: gps_lat, lng: gps_lng, recorded_at: Time.current)
    else
      GpsLog.create!(trip: trip, lat: gps_lat, lng: gps_lng, recorded_at: Time.current)
    end

    if bus_stop.sequence >= debug_target.sequence
      return render json: {
        bus_stop: bus_stop.name, target_stop: debug_target.name,
        bus_lat: gps_lat, bus_lng: gps_lng,
        eta_minutes: 0, stops_away: 0,
        bar_pct: 90, message: "현위치 도착"
      }
    end

    ahead         = all_stops.select { |s| s.sequence > bus_stop.sequence && s.sequence <= debug_target.sequence }
    total_seconds = if pct > 0 && ahead.size == 1
      (ahead.first.avg_travel_seconds.to_i * (1.0 - pct / 100.0)).ceil
    else
      ahead.sum { |s| s.avg_travel_seconds.to_i }
    end

    # 진행바 위치 계산
    bar_pct = if pct > 0 && ahead.size == 1
      30 + (90 - 30) * pct / 100  # -1 ~ 현재 구간 보간
    else
      case ahead.size
      when 1 then 30
      when 2 then 15
      else 3
      end
    end

    render json: {
      bus_stop:    bus_stop.name,
      target_stop: debug_target.name,
      bus_lat:     gps_lat,
      bus_lng:     gps_lng,
      eta_minutes: (total_seconds / 60.0).ceil,
      stops_away:  ahead.size,
      bar_pct:     bar_pct.round,
      via:         ahead.map(&:name)
    }
  end

  def like
    stop = Stop.find_by(id: params[:stop_id])
    return render json: { error: "not found" }, status: :not_found unless stop

    token  = session[:like_token] ||= SecureRandom.hex(16)
    # 좋아요는 stop/route 단위 집계이고 ETA와 무관하므로 배정된 버스 중 어느 걸 bus_id로
    # 남기는지는 중요하지 않다 — 첫 번째 버스로 단순 유지.
    bus_id = stop.route&.buses&.first&.id
    # NOTE: session 기반 중복 방지는 쿠키 삭제/시크릿 모드로 우회 가능. MVP 단계 의도된 트레이드오프.
    return render json: { error: "data error" }, status: :unprocessable_entity unless bus_id

    already_liked = StopLike.where(stop_id: stop.id, session_token: token)
                             .where("created_at > ?", 1.hour.ago).exists?

    unless already_liked
      begin
        StopLike.create!(stop_id: stop.id, bus_id: bus_id, session_token: token)
      rescue ActiveRecord::RecordNotUnique
        # 동시 요청으로 인한 중복 — 무시하고 현재 카운트 반환
      end
    end

    render json: {
      count: StopLike.where(stop_id: stop.id).count,
      already_liked: true
    }
  end
end
