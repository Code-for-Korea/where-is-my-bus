require "test_helper"

class RouteSegmentStatAggregatorJobTest < ActiveJob::TestCase
  setup do
    @bus = buses(:one)
    @stop1 = stops(:one)
    @stop2 = stops(:two)
    RouteBus.create!(route: routes(:one), bus: @bus)
  end

  test "arrive 이벤트로 구간 통계를 집계한다" do
    depart_time = Time.zone.parse("2026-10-18T10:00:00Z")
    StopEvent.create!(bus: @bus, stop: @stop1, event_type: "depart", occurred_at: depart_time, dedup_key: "jd1")
    arrive_event = StopEvent.create!(bus: @bus, stop: @stop2, event_type: "arrive", occurred_at: depart_time + 90.seconds, dedup_key: "ja1")

    RouteSegmentStatAggregatorJob.perform_now(arrive_event_id: arrive_event.id)

    stat = RouteSegmentStat.sole
    assert_equal @stop1.id, stat.from_stop_id
    assert_equal @stop2.id, stat.to_stop_id
    assert_in_delta 90.0, stat.avg_seconds, 0.001
  end

  test "존재하지 않는 이벤트 id로도 실패하지 않는다" do
    assert_nothing_raised do
      RouteSegmentStatAggregatorJob.perform_now(arrive_event_id: -1)
    end
    assert_equal 0, RouteSegmentStat.count
  end
end
