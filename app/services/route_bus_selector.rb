# route.buses(배정된 버스, N대)를 훑어 승객 화면에 보여줄 버스 하나를 고른다.
# - 활성 trip이 있는 버스가 하나도 없으면 상태는 :no_trip
# - 활성 trip은 있지만 GPS가 있는 버스가 하나도 없으면 :no_gps
# - 그 외에는 target_stop까지 stops_away가 가장 적은 버스를 선택해 :ok
#
# StopsController의 arrival/detail이 공유한다(둘 다 "배정된 버스 중 활성 trip 있는 버스,
# 여러 대면 stops_away 최소인 버스"라는 동일한 선택 기준을 따라야 하므로).
class RouteBusSelector
  Selection = Struct.new(:status, :bus, :progress, keyword_init: true)

  def self.call(route, target_stop)
    new(route, target_stop).call
  end

  def initialize(route, target_stop)
    @route = route
    @target_stop = target_stop
  end

  def call
    entries = @route.buses.map { |bus| [ bus, RouteProgress.new(bus) ] }
    with_trip = entries.reject { |_bus, progress| progress.status == :no_trip }
    return Selection.new(status: :no_trip, bus: nil, progress: nil) if with_trip.empty?

    with_gps = with_trip.select { |_bus, progress| progress.status == :ok }
    return Selection.new(status: :no_gps, bus: nil, progress: nil) if with_gps.empty?

    best_bus, best_progress = with_gps.min_by { |_bus, progress| progress.eta_to(@target_stop)&.fetch(:stops_away) || Float::INFINITY }
    Selection.new(status: :ok, bus: best_bus, progress: best_progress)
  end
end
