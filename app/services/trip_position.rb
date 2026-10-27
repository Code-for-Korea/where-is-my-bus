# 진행 중인 운행의 "이전·현재·다음 정류장". 운전자 앱이 서버가 버스 위치를 어떻게 보고 있는지 확인하는 용도다.
# 위치는 정류장 방문 기록(Geofence 진입/이탈)만으로 판단한다 — 좌표를 계산하지 않는다.
#
#   가장 최근 방문이 열려 있음(정차 중)  → 이전 = 앞 정류장, 현재 = 그 정류장, 다음 = 뒤 정류장
#   가장 최근 방문이 닫혀 있음(막 출발)  → 이전 = 방금 떠난 정류장, 현재 = 없음, 다음 = 뒤 정류장
#   아직 방문 기록이 없음               → 이전·현재 = 없음, 다음 = 첫 정류장
#   해당 방향에 정류장이 없으면 nil이다 (첫 정류장의 이전, 마지막 정류장의 다음).
class TripPosition
  Result = Struct.new(:previous, :current, :next, keyword_init: true) do
    # 앱에 내려줄 JSON: 정류장 이름만 담는다.
    def to_h
      { previous: previous&.name, current: current&.name, next: self.next&.name }
    end
  end

  def self.call(trip)
    new(trip).call
  end

  def initialize(trip)
    @route_stops = trip.route.route_stops.includes(:stop).to_a
    @visit = trip.stop_visits.order(entered_at: :desc, id: :desc).first
  end

  def call
    index = @visit && @route_stops.index { |route_stop| route_stop.stop_id == @visit.stop_id }
    return Result.new(next: stop_at(0)) unless index

    if @visit.open?
      Result.new(previous: stop_at(index - 1), current: stop_at(index), next: stop_at(index + 1))
    else
      Result.new(previous: stop_at(index), next: stop_at(index + 1))
    end
  end

  private

  def stop_at(index)
    return nil if index.negative?

    @route_stops[index]&.stop
  end
end
