require "test_helper"

class RetentionJobTest < ActiveJob::TestCase
  setup do
    @bus = buses(:one)
    @route = routes(:one)
    @from_stop = stops(:one)
    @to_stop = stops(:two)
  end

  test "24시간이 지난 PositionHistory와 GpsLog를 삭제한다" do
    old_trip = Trip.create!(bus: @bus, started_at: 25.hours.ago, ended_at: 24.hours.ago)
    GpsLog.create!(trip: old_trip, lat: 35.0, lng: 128.0, recorded_at: 25.hours.ago)
    CurrentPosition.create!(bus: @bus, lat: 35.0, lng: 128.0, recorded_at: 25.hours.ago, received_at: 25.hours.ago)
    PositionHistory.create!(bus: @bus, lat: 35.0, lng: 128.0, recorded_at: 25.hours.ago, received_at: 25.hours.ago)

    recent_trip = Trip.create!(bus: buses(:two), started_at: 30.minutes.ago)
    recent_gps = GpsLog.create!(trip: recent_trip, lat: 35.0, lng: 128.0, recorded_at: 10.minutes.ago)
    recent_history = PositionHistory.create!(bus: buses(:two), lat: 35.0, lng: 128.0, recorded_at: 10.minutes.ago, received_at: 10.minutes.ago)

    RetentionJob.perform_now

    assert_equal 0, PositionHistory.where("recorded_at < ?", 24.hours.ago).count
    assert_equal 0, GpsLog.where("recorded_at < ?", 24.hours.ago).count
    assert PositionHistory.exists?(recent_history.id)
    assert GpsLog.exists?(recent_gps.id)
  end

  test "7일이 지난 StopEvent를 삭제한다" do
    old_event = StopEvent.create!(
      bus: @bus,
      stop: @from_stop,
      event_type: "arrive",
      occurred_at: 8.days.ago,
      dedup_key: "old-event"
    )
    recent_event = StopEvent.create!(
      bus: @bus,
      stop: @from_stop,
      event_type: "arrive",
      occurred_at: 1.day.ago,
      dedup_key: "recent-event"
    )

    RetentionJob.perform_now

    assert_not StopEvent.exists?(old_event.id)
    assert StopEvent.exists?(recent_event.id)
  end

  test "90일이 지난 RouteSegmentStat를 삭제한다" do
    old_stat = RouteSegmentStat.create!(
      route: @route,
      from_stop: @from_stop,
      to_stop: @to_stop,
      hour_of_day: 12,
      date: 91.days.ago.to_date,
      avg_seconds: 120.0,
      samples_count: 10
    )
    recent_stat = RouteSegmentStat.create!(
      route: @route,
      from_stop: @from_stop,
      to_stop: @to_stop,
      hour_of_day: 12,
      date: 1.day.ago.to_date,
      avg_seconds: 120.0,
      samples_count: 10
    )

    RetentionJob.perform_now

    assert_not RouteSegmentStat.exists?(old_stat.id)
    assert RouteSegmentStat.exists?(recent_stat.id)
  end
end
