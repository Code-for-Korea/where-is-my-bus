require "test_helper"

# 1번 노선은 터미널 → 시장 → 병원.
class SegmentTimesTest < ActiveSupport::TestCase
  test "각 구간의 중앙값을 낸다" do
    finished_trip(terminal_to_market: 100, market_to_hospital: 200)
    finished_trip(terminal_to_market: 120, market_to_hospital: 220)
    finished_trip(terminal_to_market: 400, market_to_hospital: 180)

    times = SegmentTimes.call(routes(:one))

    assert_equal 120, times[[ stops(:terminal).id, stops(:market).id ]]
    assert_equal 200, times[[ stops(:market).id, stops(:hospital).id ]]
  end

  test "표본이 부족한 구간은 결과에 없다" do
    build_history(times: SegmentTimes::MIN_SAMPLES - 1, terminal_to_market: 100, market_to_hospital: 200)

    assert_empty SegmentTimes.call(routes(:one))
  end

  test "한 시간이 넘는 구간은 이상치로 버린다" do
    build_history(times: 3, terminal_to_market: 100, market_to_hospital: 200)
    finished_trip(terminal_to_market: 2.hours.to_i, market_to_hospital: 200)

    assert_equal 100, SegmentTimes.call(routes(:one))[[ stops(:terminal).id, stops(:market).id ]]
  end

  test "아직 진행 중인 운행은 표본에 넣지 않는다" do
    assert_empty SegmentTimes.call(routes(:one)) # 픽스처의 active_one만 있다
  end

  test "이웃하지 않는 정류장 사이(중간을 건너뜀)는 구간으로 세지 않는다" do
    3.times do
      t = Time.current - 5.hours
      trip = Trip.create!(bus: buses(:two), route: routes(:one), started_at: t, ended_at: t + 1.hour)
      trip.stop_visits.create!(stop: stops(:terminal), entered_at: t, exited_at: t + 10)
      trip.stop_visits.create!(stop: stops(:hospital), entered_at: t + 300, exited_at: t + 320)
    end

    assert_empty SegmentTimes.call(routes(:one))
  end
end
