require "test_helper"

class RouteSegmentStatAggregatorTest < ActiveSupport::TestCase
  setup do
    @bus = buses(:one)
    @route = routes(:one)
    @stop1 = stops(:one)
    @stop2 = stops(:two)
    RouteBus.create!(route: @route, bus: @bus)
  end

  test "depart → arrive 쌍으로 구간 통계를 생성한다" do
    depart_time = Time.zone.parse("2026-10-18T10:00:00Z")
    arrive_time = depart_time + 120.seconds
    StopEvent.create!(bus: @bus, stop: @stop1, event_type: "depart", occurred_at: depart_time, dedup_key: "d1")
    arrive_event = StopEvent.create!(bus: @bus, stop: @stop2, event_type: "arrive", occurred_at: arrive_time, dedup_key: "a1")

    RouteSegmentStatAggregator.call(arrive_event: arrive_event)

    stat = RouteSegmentStat.sole
    assert_equal @route.id, stat.route_id
    assert_equal @stop1.id, stat.from_stop_id
    assert_equal @stop2.id, stat.to_stop_id
    assert_equal arrive_time.hour, stat.hour_of_day
    assert_equal arrive_time.to_date, stat.date
    assert_in_delta 120.0, stat.avg_seconds, 0.001
    assert_equal 1, stat.samples_count
  end

  test "같은 구간·같은 시간대 누적 시 표본 평균으로 병합한다" do
    first_depart = Time.zone.parse("2026-10-18T10:00:00Z")
    first_arrive = first_depart + 120.seconds
    StopEvent.create!(bus: @bus, stop: @stop1, event_type: "depart", occurred_at: first_depart, dedup_key: "d1")
    first = StopEvent.create!(bus: @bus, stop: @stop2, event_type: "arrive", occurred_at: first_arrive, dedup_key: "a1")
    RouteSegmentStatAggregator.call(arrive_event: first)

    second_depart = first_arrive + 5.minutes
    second_arrive = second_depart + 180.seconds
    StopEvent.create!(bus: @bus, stop: @stop1, event_type: "depart", occurred_at: second_depart, dedup_key: "d2")
    second = StopEvent.create!(bus: @bus, stop: @stop2, event_type: "arrive", occurred_at: second_arrive, dedup_key: "a2")
    RouteSegmentStatAggregator.call(arrive_event: second)

    assert_equal 1, RouteSegmentStat.count
    stat = RouteSegmentStat.sole
    assert_equal 2, stat.samples_count
    assert_in_delta 150.0, stat.avg_seconds, 0.001
  end

  test "이전 depart가 없으면 통계를 생성하지 않는다" do
    arrive_event = StopEvent.create!(bus: @bus, stop: @stop2, event_type: "arrive", occurred_at: Time.zone.parse("2026-10-18T10:00:00Z"), dedup_key: "a1")

    RouteSegmentStatAggregator.call(arrive_event: arrive_event)

    assert_equal 0, RouteSegmentStat.count
  end

  test "인접하지 않은 정류장 쌍은 통계를 생성하지 않는다" do
    @stop3 = stops(:three)
    depart_time = Time.zone.parse("2026-10-18T10:00:00Z")
    StopEvent.create!(bus: @bus, stop: @stop1, event_type: "depart", occurred_at: depart_time, dedup_key: "d1")
    arrive_event = StopEvent.create!(bus: @bus, stop: @stop3, event_type: "arrive", occurred_at: depart_time + 300.seconds, dedup_key: "a3")

    RouteSegmentStatAggregator.call(arrive_event: arrive_event)

    assert_equal 0, RouteSegmentStat.count
  end

  test "arrive가 아닌 이벤트로는 집계하지 않는다" do
    approach_event = StopEvent.create!(bus: @bus, stop: @stop2, event_type: "approach", occurred_at: Time.zone.parse("2026-10-18T10:00:00Z"), dedup_key: "ap1")

    RouteSegmentStatAggregator.call(arrive_event: approach_event)

    assert_equal 0, RouteSegmentStat.count
  end

  test "MAX_SEGMENT_SECONDS를 초과하는 소요 시간은 집계하지 않는다" do
    depart_time = Time.zone.parse("2026-10-18T10:00:00Z")
    StopEvent.create!(bus: @bus, stop: @stop1, event_type: "depart", occurred_at: depart_time, dedup_key: "d1")
    arrive_event = StopEvent.create!(bus: @bus, stop: @stop2, event_type: "arrive", occurred_at: depart_time + 3.hours, dedup_key: "a1")

    RouteSegmentStatAggregator.call(arrive_event: arrive_event)

    assert_equal 0, RouteSegmentStat.count
  end

  test "arrive_event가 nil이면 아무 것도 하지 않는다" do
    RouteSegmentStatAggregator.call(arrive_event: nil)

    assert_equal 0, RouteSegmentStat.count
  end
end
