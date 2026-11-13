# 승객이 기다리는 정류장(stop)을 기준으로, 노선(route)을 운행 중인 버스마다 지금 어디쯤인지 계산한다.
# 위치는 Geofence 이벤트로 쌓인 방문 기록(StopVisit)만으로 판단한다 — 운행의 가장 최근 방문이
# 아직 열려 있으면 그 정류장에 정차 중이고, 닫혀 있으면 그 정류장을 막 출발한 것이다.
# 정차 순서는 sequence 값이 아니라 노선 안에서의 위치(목록 순번)로 비교한다 (순서에 빈 번호가 있어도 안전).
#
# kind:
#   :arriving    내 정류장에 정차 중
#   :approaching 내 정류장을 향해 오는 중 (stops_left = 내 정류장까지 도착해야 할 정류장 수, 내 정류장 포함,
#                eta_seconds = 도착까지 추정 초. 구간 통계가 부족하면 nil — 화면은 정류장 수만 보여준다)
#   :unknown     운행 중이지만 아직 어느 정류장에서도 이벤트가 없다 (위치 확인 중)
#   :passed      이미 내 정류장을 지났다
class RouteBusStatuses
  Status = Struct.new(:bus, :kind, :last_stop, :at_last_stop, :stops_left, :eta_seconds, keyword_init: true)

  DWELL_SECONDS = 20 # 중간 정류장 정차 시간 가정값 (정류장별 통계는 아직 없다)

  RANK = { arriving: 0, approaching: 1, unknown: 2, passed: 3 }.freeze

  def self.call(route:, stop:)
    new(route, stop).call
  end

  def initialize(route, stop)
    @route = route
    @stop = stop
  end

  def call
    @stop_ids = @route.route_stops.map(&:stop_id)
    @target = @stop_ids.index(@stop.id)
    return [] unless @target

    trips = @route.trips.active.includes(:bus).to_a
    latest = latest_visits(trips)

    trips.map { |trip| status_for(trip.bus, latest[trip.id]) }
         .sort_by { |status| [ RANK.fetch(status.kind), status.stops_left || 0 ] }
  end

  private

  # 운행별로 가장 최근 방문 기록 하나.
  def latest_visits(trips)
    StopVisit.where(trip_id: trips.map(&:id)).includes(:stop)
             .order(entered_at: :desc, id: :desc)
             .group_by(&:trip_id)
             .transform_values(&:first)
  end

  # 내 정류장까지의 추정 초: (정차 중이면 남은 정차 시간) + 구간 소요 시간들 + 중간 정류장 정차 시간.
  # 막 출발한 경우 첫 구간은 이미 지난 시간만큼 뺀다. 구간 통계가 하나라도 없으면 nil.
  def eta_seconds(visit, position)
    now = Time.current
    total = visit.open? ? [ DWELL_SECONDS - (now - visit.entered_at), 0 ].max : 0

    (position...@target).each do |index|
      travel = segment_times[[ @stop_ids[index], @stop_ids[index + 1] ]] or return nil
      travel = [ travel - (now - visit.exited_at), 0 ].max if index == position && !visit.open?
      total += travel
      total += DWELL_SECONDS if index + 1 < @target
    end
    total.round
  end

  def segment_times
    @segment_times ||= SegmentTimes.call(@route)
  end

  def status_for(bus, visit)
    position = visit && @stop_ids.index(visit.stop_id)
    return Status.new(bus: bus, kind: :unknown) unless position

    base = { bus: bus, last_stop: visit.stop, at_last_stop: visit.open? }

    if position == @target && visit.open?
      Status.new(**base, kind: :arriving, stops_left: 0)
    elsif position >= @target
      Status.new(**base, kind: :passed)
    else
      Status.new(**base, kind: :approaching, stops_left: @target - position, eta_seconds: eta_seconds(visit, position))
    end
  end
end
