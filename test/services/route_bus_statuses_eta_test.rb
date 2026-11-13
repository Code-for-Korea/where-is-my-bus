require "test_helper"

# 구간 통계(터미널→시장 120초, 시장→병원 180초)가 있을 때의 도착 예상 시간.
# 픽스처: 버스 one은 터미널을 떠나 지금 시장에 10분째 정차 중이다.
class RouteBusStatusesEtaTest < ActiveSupport::TestCase
  setup { build_history(terminal_to_market: 120, market_to_hospital: 180) }

  def status_for(stop)
    RouteBusStatuses.call(route: routes(:one), stop: stop).find { |s| s.bus == buses(:one) }
  end

  test "정차가 길어졌으면 남은 정차 시간 없이 다음 구간 시간만 센다" do
    assert_equal 180, status_for(stops(:hospital)).eta_seconds
  end

  test "막 출발했으면 이미 지난 시간만큼 첫 구간에서 뺀다" do
    stop_visits(:at_market).update!(exited_at: 60.seconds.ago)

    assert_in_delta 120, status_for(stops(:hospital)).eta_seconds, 2
  end

  test "구간 시간보다 오래 걸리면 0초 밑으로 내려가지 않는다" do
    stop_visits(:at_market).update!(exited_at: 10.minutes.ago)

    assert_equal 0, status_for(stops(:hospital)).eta_seconds
  end

  test "두 정류장 뒤면 구간 시간과 중간 정류장 정차 시간을 더한다" do
    bus = buses(:two)
    trip = Trip.create!(bus: bus, route: routes(:one), started_at: 10.minutes.ago)
    trip.stop_visits.create!(stop: stops(:terminal), entered_at: 5.minutes.ago)

    status = RouteBusStatuses.call(route: routes(:one), stop: stops(:hospital)).find { |s| s.bus == bus }

    assert_equal 120 + RouteBusStatuses::DWELL_SECONDS + 180, status.eta_seconds
  end

  test "구간 통계가 없으면 ETA는 nil이다" do
    Trip.where.not(ended_at: nil).where(route: routes(:one)).destroy_all

    assert_nil status_for(stops(:hospital)).eta_seconds
  end

  test "정차 중이거나 지나간 버스에는 ETA가 없다" do
    assert_nil status_for(stops(:market)).eta_seconds   # arriving
    assert_nil status_for(stops(:terminal)).eta_seconds # passed
  end
end
