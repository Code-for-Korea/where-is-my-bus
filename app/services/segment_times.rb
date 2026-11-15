# 노선의 인접 정류장 구간별 소요 시간(초) 중앙값 — 끝난 운행들의 방문 기록에서 배운다.
# 구간 시간 = 앞 정류장을 떠난 시각(exited_at) → 다음 정류장에 들어선 시각(entered_at). 정차 시간은 포함하지 않는다.
#
# 표본이 MIN_SAMPLES보다 적은 구간은 결과에서 뺀다. 호출하는 쪽은 구간이 하나라도 없으면 ETA를 내지 않는다.
# 통계를 테이블로 두지 않고 최근 운행에서 그때그때 계산한 뒤 캐시한다 (docs/design-realtime-eta.md 5절).
#
#   SegmentTimes.call(route) # => { [from_stop_id, to_stop_id] => 중앙값(초) }
class SegmentTimes
  RECENT_TRIPS = 30
  MIN_SAMPLES = 3
  MAX_SECONDS = 1.hour.to_i # 이보다 길면 운행 중단·단말 꺼짐 등 이상치로 보고 버린다
  CACHE_TTL = 10.minutes

  def self.call(route)
    Rails.cache.fetch("segment_times/#{route.id}", expires_in: CACHE_TTL) { new(route).call }
  end

  def initialize(route)
    @route = route
  end

  def call
    stop_ids = @route.route_stops.map(&:stop_id)
    next_stop = stop_ids.each_cons(2).to_h

    samples = Hash.new { |hash, key| hash[key] = [] }
    visits_by_trip.each_value do |visits|
      visits.each_cons(2) do |from, to|
        next unless next_stop[from.stop_id] == to.stop_id && from.exited_at

        seconds = to.entered_at - from.exited_at
        samples[[ from.stop_id, to.stop_id ]] << seconds if seconds.positive? && seconds <= MAX_SECONDS
      end
    end

    samples.select { |_, list| list.size >= MIN_SAMPLES }.transform_values { |list| median(list).round }
  end

  private

  def visits_by_trip
    trip_ids = @route.trips.where.not(ended_at: nil).order(ended_at: :desc).limit(RECENT_TRIPS).ids
    StopVisit.where(trip_id: trip_ids).order(:entered_at).group_by(&:trip_id)
  end

  def median(list)
    sorted = list.sort
    middle = sorted.size / 2
    sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
  end
end
