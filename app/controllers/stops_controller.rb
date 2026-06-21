class StopsController < ApplicationController
  allow_unauthenticated_access
  before_action :no_turbo_cache, only: %i[show detail]

  def show
    @stop   = Stop.find_by(id: params[:stop_id])
    @bus    = @stop&.route&.bus
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

    @bus    = @stop.route&.bus
    @region = @bus&.region
    @area   = @bus&.area
    return render json: { error: "data error" }, status: :unprocessable_entity if @bus.nil? || @region.nil?

    @likes_count = StopLike.where(stop_id: @stop.id).count
    load_selector_regions

    all_stops = @stop.route.stops.order(:sequence).to_a

    trip, latest_gps = active_trip_with_gps(@bus)
    bus_stop = nearest_stop(all_stops, latest_gps)

    @route_stops = all_stops.map do |s|
      { seq: s.sequence, name: s.display_name,
        current_bus: bus_stop&.id == s.id,
        here: @stop.id == s.id }
    end
  end

  def arrival
    target_stop = Stop.find_by(id: params[:stop_id])
    return render json: { status: "no_data", eta_minutes: nil, stops_away: nil } unless target_stop

    bus = target_stop.route&.bus
    return render json: { status: "no_data", eta_minutes: nil, stops_away: nil } unless bus

    trip, latest_gps = active_trip_with_gps(bus)
    return render json: { eta_minutes: nil, stops_away: nil, bus_number: bus.bus_number, status: "no_trip" } unless trip
    return render json: { status: "no_data", eta_minutes: nil, stops_away: nil, bus_number: bus.bus_number } unless latest_gps

    all_stops = target_stop.route.stops.order(:sequence).to_a
    bus_stop  = nearest_stop(all_stops, latest_gps)
    return render json: { status: "no_data", eta_minutes: nil, stops_away: nil, bus_number: bus.bus_number } unless bus_stop

    if bus_stop.sequence >= target_stop.sequence
      # 마지막 구간(-1 → 현재) 진행률 계산
      prev_stop = all_stops.find { |s| s.sequence == target_stop.sequence - 1 }
      seg_seconds = target_stop.avg_travel_seconds.to_i

      progress = if prev_stop
        seg_len = Math.sqrt(
          (target_stop.lat.to_f - prev_stop.lat.to_f)**2 +
          (target_stop.lng.to_f - prev_stop.lng.to_f)**2
        )
        bus_dist = Math.sqrt(
          (latest_gps.lat.to_f - prev_stop.lat.to_f)**2 +
          (latest_gps.lng.to_f - prev_stop.lng.to_f)**2
        )
        seg_len > 0 ? [ bus_dist / seg_len, 1.0 ].min : 1.0
      else
        1.0
      end

      # progress < 1.0: 마지막 구간 진입 중 → stops_away: 1 유지
      if progress < 1.0
        remaining = seg_seconds > 0 ? (seg_seconds * (1.0 - progress)).ceil : 0
        return render json: {
          eta_minutes: (remaining / 60.0).ceil,
          stops_away:  1,
          bus_number:  bus.bus_number,
          bar_pct:     [ (30 + (90 - 30) * progress).round, 89 ].min
        }
      end

      # progress >= 1.0: 실제 도착
      return render json: {
        eta_minutes: 0,
        stops_away:  0,
        bus_number:  bus.bus_number,
        bar_pct:     90
      }
    end

    ahead = all_stops.select { |s| s.sequence > bus_stop.sequence && s.sequence <= target_stop.sequence }
    total_seconds = ahead.sum { |s| s.avg_travel_seconds.to_i }
    bar_pct = case ahead.size
    when 1 then 30
    when 2 then 15
    else        3
    end

    render json: {
      eta_minutes: (total_seconds / 60.0).ceil,
      stops_away:  ahead.size,
      bus_number:  bus.bus_number,
      bar_pct:     bar_pct
    }
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

    trip = route.bus.trips.where(ended_at: nil).order(started_at: :desc).first
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
    bus_id = stop.route&.bus_id
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

  private

  # 현재 운행 중인 trip과 최신 GPS 로그를 함께 반환
  # @return [Array(Trip|nil, GpsLog|nil)]
  def active_trip_with_gps(bus)
    trip = bus.trips.where(ended_at: nil).order(started_at: :desc).first
    return [ nil, nil ] unless trip

    latest_gps = trip.gps_logs.order(recorded_at: :desc).first
    [ trip, latest_gps ]
  end

  # GPS 좌표에 가장 가까운 정류장을 반환 (gps가 nil이면 nil 반환)
  # 경도 방향에 위도 보정(cos factor)을 적용해 실제 거리에 근사
  def nearest_stop(all_stops, gps)
    return nil unless gps

    lat_factor = Math.cos(gps.lat.to_f * Math::PI / 180)
    all_stops.min_by do |s|
      dlat = s.lat.to_f - gps.lat.to_f
      dlng = (s.lng.to_f - gps.lng.to_f) * lat_factor
      dlat**2 + dlng**2
    end
  end
end
