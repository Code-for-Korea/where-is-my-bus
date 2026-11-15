require "test_helper"

class ArrivalPresenterEtaTest < ActiveSupport::TestCase
  def presenter_with(eta_seconds)
    status = RouteBusStatuses::Status.new(bus: buses(:one), kind: :approaching, last_stop: stops(:market),
                                          at_last_stop: true, stops_left: 1, eta_seconds: eta_seconds)
    ArrivalPresenter.new(statuses: [ status ], route_stops: routes(:one).route_stops.includes(:stop), stop: stops(:hospital))
  end

  test "ETA가 있으면 분 단위로 올림해 보여준다" do
    assert_equal [ "약 3분 후", "도착 예정입니다." ], presenter_with(180).big_lines
    assert_equal [ "약 4분 후", "도착 예정입니다." ], presenter_with(181).big_lines
  end

  test "1분 미만이면 곧 도착이다" do
    assert_equal [ "곧", "도착합니다." ], presenter_with(59).big_lines
  end

  test "ETA가 없으면 남은 정류장 수로 보여준다" do
    assert_equal [ "1정거장 전에", "있습니다." ], presenter_with(nil).big_lines
  end

  test "다른 버스 요약에도 ETA를 쓴다" do
    first = RouteBusStatuses::Status.new(bus: buses(:one), kind: :arriving, stops_left: 0)
    other = RouteBusStatuses::Status.new(bus: buses(:two), kind: :approaching, last_stop: stops(:terminal),
                                         at_last_stop: false, stops_left: 2, eta_seconds: 300)
    presenter = ArrivalPresenter.new(statuses: [ first, other ], route_stops: routes(:one).route_stops.includes(:stop), stop: stops(:hospital))

    assert_match(/약 5분 후 도착/, presenter.others.sole)
  end
end
