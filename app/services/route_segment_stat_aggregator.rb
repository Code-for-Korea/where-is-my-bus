# frozen_string_literal: true

# 정류장 이벤트 쌍(depart → arrive)으로부터 인접 구간의 소요 시간을
# RouteSegmentStat에 집계한다. 집계 단위는
# (route, from_stop, to_stop, hour_of_day, date)이며 unique index로 중복을 막는다.
#
# 정책:
# - depart(from_stop) → arrive(to_stop) 이벤트 시각 차이가 구간 소요 시간.
# - to_stop은 from_stop 바로 다음 순번(sequence + 1)인 경우만 인정.
# - 소요 시간은 0초 초과, MAX_SEGMENT_SECONDS 이하만 인정(자정 걸침·이상치 방지).
# - hour_of_day/date는 arrive 시각 기준.
# - 같은 버스 이벤트가 순차 발생하므로 경쟁은 드물지만, create 충돌 시 재조회로 병합한다.
class RouteSegmentStatAggregator
  MAX_SEGMENT_SECONDS = 2 * 60 * 60

  def self.call(arrive_event:)
    new(arrive_event).call
  end

  def initialize(arrive_event)
    @arrive_event = arrive_event
  end

  def call
    return if @arrive_event.nil? || @arrive_event.event_type != "arrive"

    depart_event = find_pairing_depart_event
    return unless depart_event

    seconds = (@arrive_event.occurred_at - depart_event.occurred_at).to_f
    return unless seconds.positive? && seconds <= MAX_SEGMENT_SECONDS

    upsert_stat(depart_event, seconds)
  end

  private

  def find_pairing_depart_event
    route = @arrive_event.bus.routes.order(:position).first
    return if route.nil?

    previous_stop = route.stops.find_by(sequence: @arrive_event.stop.sequence - 1)
    return if previous_stop.nil?

    StopEvent.where(bus: @arrive_event.bus, stop: previous_stop, event_type: "depart")
             .where("occurred_at <= ?", @arrive_event.occurred_at)
             .order(occurred_at: :desc)
             .first
  end

  def upsert_stat(depart_event, seconds)
    route = @arrive_event.bus.routes.order(:position).first
    bucket = stat_bucket(route, depart_event.stop_id)

    stat = RouteSegmentStat.find_by(**bucket)
    unless stat
      begin
        RouteSegmentStat.create!(**bucket, avg_seconds: seconds, samples_count: 1)
        return
      rescue ActiveRecord::RecordNotUnique
        stat = RouteSegmentStat.find_by(**bucket)
        return if stat.nil?
      end
    end

    new_count = stat.samples_count + 1
    new_avg = (stat.avg_seconds * stat.samples_count + seconds) / new_count
    stat.update!(avg_seconds: new_avg, samples_count: new_count)
  end

  def stat_bucket(route, from_stop_id)
    occurred = @arrive_event.occurred_at.in_time_zone
    {
      route_id: route.id,
      from_stop_id: from_stop_id,
      to_stop_id: @arrive_event.stop_id,
      hour_of_day: occurred.hour,
      date: occurred.to_date
    }
  end
end
