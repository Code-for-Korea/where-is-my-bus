require "test_helper"

# 픽스처: 1번 노선은 터미널 → 시장 → 병원. 버스 one의 운행은 터미널을 출발했고 지금 시장에 정차 중이다.
class RouteBusStatusesTest < ActiveSupport::TestCase
  def statuses_for(stop, route = routes(:one))
    RouteBusStatuses.call(route: route, stop: stop)
  end

  test "a bus stopped at the previous stop is approaching with one stop left" do
    status = statuses_for(stops(:hospital)).sole

    assert_equal :approaching, status.kind
    assert_equal 1, status.stops_left
    assert_equal stops(:market), status.last_stop
    assert status.at_last_stop
    assert_equal buses(:one), status.bus
  end

  test "a bus stopped at my stop is arriving" do
    status = statuses_for(stops(:market)).sole

    assert_equal :arriving, status.kind
    assert_equal 0, status.stops_left
  end

  test "a bus already beyond my stop has passed" do
    status = statuses_for(stops(:terminal)).sole

    assert_equal :passed, status.kind
    assert_equal stops(:market), status.last_stop
  end

  test "a bus that just left the previous stop is still approaching" do
    stop_visits(:at_market).update!(exited_at: 1.minute.ago)

    status = statuses_for(stops(:hospital)).sole

    assert_equal :approaching, status.kind
    assert_equal 1, status.stops_left
    assert_not status.at_last_stop
  end

  test "a bus that just left my stop has passed" do
    stop_visits(:at_market).update!(exited_at: 1.minute.ago)

    assert_equal :passed, statuses_for(stops(:market)).sole.kind
  end

  test "a running bus with no stop visit yet has an unknown position" do
    Trip.create!(bus: buses(:two), route: routes(:one), started_at: 5.minutes.ago)

    unknown = statuses_for(stops(:hospital)).find { |s| s.bus == buses(:two) }

    assert_equal :unknown, unknown.kind
    assert_nil unknown.last_stop
  end

  test "buses are ordered arriving, approaching by distance, unknown, then passed" do
    far = Trip.create!(bus: buses(:two), route: routes(:one), started_at: 5.minutes.ago)
    far.stop_visits.create!(stop: stops(:terminal), entered_at: 1.minute.ago)

    kinds = statuses_for(stops(:hospital)).map { |s| [ s.bus, s.kind, s.stops_left ] }

    assert_equal [ [ buses(:one), :approaching, 1 ], [ buses(:two), :approaching, 2 ] ], kinds
  end

  test "uses the most recent visit of each trip" do
    trips(:active_one).stop_visits.create!(stop: stops(:hospital), entered_at: 1.minute.ago)

    status = statuses_for(stops(:hospital)).sole

    assert_equal :arriving, status.kind
  end

  test "ignores finished trips" do
    assert_empty statuses_for(stops(:school), routes(:two))
  end

  test "returns nothing when the stop is not on the route" do
    assert_empty statuses_for(stops(:school))
  end

  test "compares positions within the route, not raw sequence numbers" do
    routes(:one).route_stops.find_by(stop: stops(:terminal)).update_columns(sequence: 10)
    routes(:one).route_stops.find_by(stop: stops(:market)).update_columns(sequence: 20)
    routes(:one).route_stops.find_by(stop: stops(:hospital)).update_columns(sequence: 30)

    status = statuses_for(stops(:hospital)).sole

    assert_equal :approaching, status.kind
    assert_equal 1, status.stops_left
  end
end
