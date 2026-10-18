# route.buses(배정된 버스, N대)를 훑어 버스를 선택한다.
# - :passenger (기본): 승객 화면에 보여줄 단일 추천 버스를 고른다.
# - :map / :admin: 배차된 버스 중 GPS(활성 trip + 최신 위치)가 있는 모든 버스를 반환한다.
#
# StopsController의 arrival/detail과 MapController가 공유한다.
class RouteBusSelector
  Selection = Struct.new(:status, :bus, :progress, keyword_init: true)

  def self.call(route, target_stop = nil, context: :passenger)
    new(route, target_stop, context: context).call
  end

  def initialize(route, target_stop, context: :passenger)
    @route = route
    @target_stop = target_stop
    @context = context
  end

  def call
    case @context
    when :map, :admin
      all_with_gps
    else
      single_best
    end
  end

  private

  def all_with_gps
    @route.buses.map { |bus| build_entry(bus) }.select { |entry| entry.status == :ok }
  end

  def single_best
    entries = @route.buses.map { |bus| build_entry(bus) }
    with_trip = entries.reject { |entry| entry.status == :no_trip }
    return Selection.new(status: :no_trip, bus: nil, progress: nil) if with_trip.empty?

    with_gps = with_trip.select { |entry| entry.status == :ok }
    return Selection.new(status: :no_gps, bus: nil, progress: nil) if with_gps.empty?

    best_entry = with_gps.min_by { |entry| entry.progress.eta_to(@target_stop)&.fetch(:stops_away) || Float::INFINITY }
    Selection.new(status: :ok, bus: best_entry.bus, progress: best_entry.progress)
  end

  def build_entry(bus)
    progress = RouteProgress.new(bus)
    Selection.new(status: progress.status, bus: bus, progress: progress)
  end
end
