require "test_helper"

# 픽스처: 1번 노선은 터미널 → 시장 → 병원. 버스 one은 터미널을 떠나 지금 시장에 정차 중이다.
class ArrivalPresenterTest < ActiveSupport::TestCase
  def presenter_for(stop, route = routes(:one))
    ArrivalPresenter.new(statuses: RouteBusStatuses.call(route: route, stop: stop),
                         route_stops: route.route_stops.includes(:stop), stop: stop)
  end

  test "approaching: where the bus is, how many stops left, and the bar at the -1 dot" do
    presenter = presenter_for(stops(:hospital))

    assert_equal "고성시장 정차 중", presenter.small
    assert_equal [ "1정거장 전에", "있습니다." ], presenter.big_lines
    assert_equal 30, presenter.bar_pct
    assert_not presenter.dim?
  end

  test "arriving: the bus is at my stop" do
    presenter = presenter_for(stops(:market))

    assert_equal "", presenter.small
    assert_equal [ "지금 정류장에", "도착했습니다." ], presenter.big_lines
    assert_equal 90, presenter.bar_pct
  end

  test "passed: dimmed bus past the pin" do
    presenter = presenter_for(stops(:terminal))

    assert_equal "고성시장 정차 중", presenter.small
    assert_equal [ "이 정류장을", "지나갔습니다." ], presenter.big_lines
    assert_equal 96, presenter.bar_pct
    assert presenter.dim?
  end

  test "no running bus: idle bar and a dimmed icon" do
    presenter = presenter_for(stops(:school), routes(:two))

    assert_equal [ "운행 중인 버스가", "없습니다." ], presenter.big_lines
    assert_equal 50, presenter.bar_pct
    assert presenter.dim?
    assert_empty presenter.others
  end

  test "unknown position: says the position is being checked" do
    trips(:active_one).update!(ended_at: Time.current)
    Trip.create!(bus: buses(:two), route: routes(:one), started_at: 1.minute.ago)

    presenter = presenter_for(stops(:hospital))

    assert_equal [ "위치를 확인하는", "중입니다." ], presenter.big_lines
    assert_equal 50, presenter.bar_pct
    assert presenter.dim?
  end

  test "the bar sits at the fixed dots: 3 stops or more at 3, 2 stops at 15, 1 stop at 30" do
    expected = { 1 => 30, 2 => 15, 3 => 3, 5 => 3 }
    expected.each do |stops_left, pct|
      status = RouteBusStatuses::Status.new(bus: buses(:one), kind: :approaching, last_stop: stops(:market), at_last_stop: true, stops_left: stops_left)

      assert_equal pct, ArrivalPresenter.new(statuses: [ status ], route_stops: [], stop: stops(:hospital)).bar_pct, "남은 정류장 #{stops_left}"
    end
  end

  test "just after leaving a stop the bar is halfway to the next dot" do
    { 1 => 60, 2 => 23, 3 => 9 }.each do |stops_left, pct| # 2정거장: 15와 30의 중간 22.5를 반올림
      status = RouteBusStatuses::Status.new(bus: buses(:one), kind: :approaching, last_stop: stops(:market), at_last_stop: false, stops_left: stops_left)

      assert_equal pct, ArrivalPresenter.new(statuses: [ status ], route_stops: [], stop: stops(:hospital)).bar_pct, "남은 정류장 #{stops_left}"
    end
  end

  test "the nearest bus is the headline and the others are summarised" do
    far = Trip.create!(bus: buses(:two), route: routes(:one), started_at: 5.minutes.ago)
    far.stop_visits.create!(stop: stops(:terminal), entered_at: 1.minute.ago)

    presenter = presenter_for(stops(:hospital))

    assert_equal [ "1정거장 전에", "있습니다." ], presenter.big_lines
    assert_equal [ "2번 · 2정거장 전" ], presenter.others
  end

  test "timeline marks my stop and lists the buses that are at each stop" do
    timeline = presenter_for(stops(:hospital)).timeline

    assert_equal %w[고성터미널 고성시장 고성병원], timeline.map { |row| row[:name] }
    assert_equal [ false, false, true ], timeline.map { |row| row[:mine] }
    assert_equal [ [], [ "1번" ], [] ], timeline.map { |row| row[:buses] }
  end

  test "to_h is what the polling endpoint returns" do
    assert_equal %i[small big barPct dim others], presenter_for(stops(:hospital)).to_h.keys
  end
end
