# 버스의 최신 GPS를 노선 정류장과 비교해 ETA를 계산한다.
# 승객 화면(StopsController#arrival)과 운전자 앱(Integrations::TraccarController#routes)이 공유.
class RouteProgress
  def initialize(bus)
    @bus = bus
  end

  def status
    return :no_trip unless trip
    return :no_gps unless latest_gps
    :ok
  end

  # target_stop까지의 도착 예정 정보. trip/gps가 없으면 nil.
  def eta_to(target_stop)
    return nil unless status == :ok

    all_stops = target_stop.route.stops.order(:sequence).to_a
    bus_stop  = nearest_stop(all_stops)
    return nil unless bus_stop

    if bus_stop.sequence >= target_stop.sequence
      # 마지막 구간(-1 → 현재) 진행률 계산
      prev_stop   = all_stops.find { |s| s.sequence == target_stop.sequence - 1 }
      seg_seconds = target_stop.avg_travel_seconds.to_i

      progress = if prev_stop
        seg_len  = distance(target_stop, prev_stop)
        bus_dist = distance(latest_gps, prev_stop)
        seg_len > 0 ? [ bus_dist / seg_len, 1.0 ].min : 1.0
      else
        1.0
      end

      if progress < 1.0
        remaining = seg_seconds > 0 ? (seg_seconds * (1.0 - progress)).ceil : 0
        return { eta_minutes: (remaining / 60.0).ceil, stops_away: 1, bar_pct: [ (30 + (90 - 30) * progress).round, 89 ].min }
      end

      return { eta_minutes: 0, stops_away: 0, bar_pct: 90 }
    end

    ahead         = all_stops.select { |s| s.sequence > bus_stop.sequence && s.sequence <= target_stop.sequence }
    total_seconds = ahead.sum { |s| s.avg_travel_seconds.to_i }
    bar_pct = case ahead.size
    when 1 then 30
    when 2 then 15
    else        3
    end

    { eta_minutes: (total_seconds / 60.0).ceil, stops_away: ahead.size, bar_pct: bar_pct }
  end

  # GPS와 가장 가까운 정류장(버스의 현재 위치로 간주). trip/gps가 없으면 nil.
  def current_stop(route)
    return nil unless status == :ok

    nearest_stop(route.stops.order(:sequence).to_a)
  end

  # 현재 위치 기준 "다음 정류장"(가장 가까운 지난 정류장의 다음)까지의 ETA. 마지막 정류장이면 nil.
  def next_stop_eta(route)
    return nil unless status == :ok

    all_stops = route.stops.order(:sequence).to_a
    bus_stop  = nearest_stop(all_stops)
    return nil unless bus_stop

    target = all_stops.find { |s| s.sequence == bus_stop.sequence + 1 }
    return nil unless target

    result = eta_to(target)
    result && result.merge(stop: target)
  end

  private

  def trip
    @trip ||= @bus.trips.where(ended_at: nil).order(started_at: :desc).first
  end

  def latest_gps
    return @latest_gps if defined?(@latest_gps)
    @latest_gps = trip&.gps_logs&.order(recorded_at: :desc)&.first
  end

  # 경도 방향에 위도 보정(cos factor)을 적용해 실제 거리에 근사
  def nearest_stop(all_stops)
    lat_factor = Math.cos(latest_gps.lat.to_f * Math::PI / 180)
    all_stops.min_by do |s|
      dlat = s.lat.to_f - latest_gps.lat.to_f
      dlng = (s.lng.to_f - latest_gps.lng.to_f) * lat_factor
      dlat**2 + dlng**2
    end
  end

  def distance(a, b)
    Math.sqrt((a.lat.to_f - b.lat.to_f)**2 + (a.lng.to_f - b.lng.to_f)**2)
  end
end
