require "test_helper"

class StopEventDetectorTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @bus = buses(:one)
    @bus.update!(traccar_unique_id: "stop-event-device")
    @route = routes(:one)
    RouteBus.find_or_create_by!(route: @route, bus: @bus)

    @stop = Stop.create!(route: @route, name: "이벤트 테스트 정류장", sequence: 999, lat: 35.100000, lng: 128.100000)
  end

  test "버스가 정류장에 접근하면 approach 이벤트를 생성한다" do
    current = CurrentPosition.create!(
      bus: @bus,
      lat: @stop.lat + 0.001,
      lng: @stop.lng + 0.001,
      recorded_at: Time.current,
      received_at: Time.current
    )

    assert_difference -> { StopEvent.where(event_type: "approach", stop: @stop).count } => 1 do
      StopEventDetector.call(bus: @bus, current_position: current)
    end
  end

  test "버스가 정류장에 도착하면 arrive 이벤트를 생성한다" do
    current = CurrentPosition.create!(
      bus: @bus,
      lat: @stop.lat,
      lng: @stop.lng,
      recorded_at: Time.current,
      received_at: Time.current
    )

    assert_difference -> { StopEvent.where(event_type: "arrive", stop: @stop).count } => 1 do
      StopEventDetector.call(bus: @bus, current_position: current)
    end
  end

  test "arrive 이벤트 생성 시 구간 통계 집계 잡을 enqueue한다" do
    current = CurrentPosition.create!(
      bus: @bus,
      lat: @stop.lat,
      lng: @stop.lng,
      recorded_at: Time.current,
      received_at: Time.current
    )

    assert_enqueued_with(job: RouteSegmentStatAggregatorJob) do
      StopEventDetector.call(bus: @bus, current_position: current)
    end
  end

  test "approach·depart 이벤트로는 집계 잡을 enqueue하지 않는다" do
    # fixture 정류장 1~3이 35.100~35.102에 몰려 있으므로, 전부 30m(도착 반경) 밖이면서
    # 테스트 정류장의 접근 반경(200m) 안인 위치를 잡는다.
    current = CurrentPosition.create!(
      bus: @bus,
      lat: @stop.lat + 0.0015,
      lng: @stop.lng,
      recorded_at: Time.current,
      received_at: Time.current
    )

    assert_no_enqueued_jobs do
      StopEventDetector.call(bus: @bus, current_position: current)
    end
    assert_equal 1, StopEvent.where(event_type: "approach", stop: @stop).count
    assert_equal 0, StopEvent.where(event_type: "arrive").count
  end

  test "버스가 정류장에서 이탈하면 depart 이벤트를 생성한다" do
    PositionHistory.create!(
      bus: @bus,
      lat: @stop.lat,
      lng: @stop.lng,
      recorded_at: 2.minutes.ago,
      received_at: 2.minutes.ago
    )
    StopEvent.create!(
      bus: @bus,
      stop: @stop,
      event_type: "arrive",
      occurred_at: 2.minutes.ago,
      dedup_key: "arrive-#{@stop.id}"
    )

    current = CurrentPosition.create!(
      bus: @bus,
      lat: @stop.lat + 0.005,
      lng: @stop.lng + 0.005,
      recorded_at: Time.current,
      received_at: Time.current
    )

    assert_difference -> { StopEvent.where(event_type: "depart", stop: @stop).count } => 1 do
      StopEventDetector.call(bus: @bus, current_position: current)
    end
  end

  test "dedup_key로 중복 이벤트를 방지한다" do
    current = CurrentPosition.create!(
      bus: @bus,
      lat: @stop.lat,
      lng: @stop.lng,
      recorded_at: Time.current,
      received_at: Time.current
    )

    assert_difference -> { StopEvent.where(event_type: "arrive", stop: @stop).count } => 1 do
      StopEventDetector.call(bus: @bus, current_position: current)
      StopEventDetector.call(bus: @bus, current_position: current)
    end
  end

  test "좌표가 없는 정류장은 스킵한다" do
    null_stop = Stop.new(route: @route, name: "좌표 없는 정류장", sequence: 998)
    null_stop.save(validate: false)

    current = CurrentPosition.create!(
      bus: @bus,
      lat: @stop.lat,
      lng: @stop.lng,
      recorded_at: Time.current,
      received_at: Time.current
    )

    assert_no_difference -> { StopEvent.where(stop: null_stop).count } do
      StopEventDetector.call(bus: @bus, current_position: current)
    end
  end

  test "정류장에서 멀어지면 approach 이벤트는 생성되지 않는다" do
    current = CurrentPosition.create!(
      bus: @bus,
      lat: @stop.lat + 0.05,
      lng: @stop.lng + 0.05,
      recorded_at: Time.current,
      received_at: Time.current
    )

    assert_no_difference -> { StopEvent.where(stop: @stop).count } do
      StopEventDetector.call(bus: @bus, current_position: current)
    end
  end
end
