require "test_helper"

class TripAutoTerminatorJobTest < ActiveJob::TestCase
  test "타임아웃 이상 GPS 없는 활성 trip을 종료한다" do
    # fixture 열운행 trip(one_active)과의 중복을 피하려고 종료 처리 후 새 trip을 만든다
    trips(:one_active).update!(ended_at: 1.hour.ago)
    trip = Trip.create!(bus: buses(:one), started_at: 30.minutes.ago)
    GpsLog.create!(trip: trip, lat: 35.100000, lng: 128.100000, recorded_at: 20.minutes.ago)

    TripAutoTerminatorJob.perform_now

    assert_not_nil trip.reload.ended_at
    assert trip.reload.ended_at <= Time.current
  end

  test "최근 GPS가 있는 활성 trip은 종료하지 않는다" do
    # 픽스처 trip(one_active/two_active)의 GpsLog는 1분 전 — 기본 10분 타임아웃으로는 생존
    TripAutoTerminatorJob.perform_now

    assert_nil trips(:one_active).reload.ended_at
    assert_nil trips(:two_active).reload.ended_at
  end

  test "GpsLog가 없어도 버스의 CurrentPosition이 오래되었으면 종료한다" do
    bus = buses(:two)
    trips(:two_active).update!(ended_at: 1.hour.ago)
    trip = Trip.create!(bus: bus, started_at: 30.minutes.ago)
    CurrentPosition.create!(bus: bus, lat: 35.100000, lng: 128.100000, recorded_at: 20.minutes.ago, received_at: 20.minutes.ago)

    TripAutoTerminatorJob.perform_now

    assert_not_nil trip.reload.ended_at
    # 종료해도 CurrentPosition은 삭제하지 않는다
    assert CurrentPosition.exists?(bus_id: bus.id)
  end

  test "GpsLog와 CurrentPosition이 모두 없으면 started_at 기준으로 판정한다" do
    trips(:one_active).update!(ended_at: 1.hour.ago)
    trips(:two_active).update!(ended_at: 1.hour.ago)
    stale_trip = Trip.create!(bus: buses(:one), started_at: 30.minutes.ago)
    recent_trip = Trip.create!(bus: buses(:two), started_at: 1.minute.ago)

    TripAutoTerminatorJob.perform_now

    assert_not_nil stale_trip.reload.ended_at
    assert_nil recent_trip.reload.ended_at
  end

  test "이미 종료된 trip은 다시 건드리지 않는다" do
    trip = Trip.create!(bus: buses(:one), started_at: 30.minutes.ago, ended_at: 5.minutes.ago)
    original_ended_at = trip.reload.ended_at

    TripAutoTerminatorJob.perform_now

    assert_equal original_ended_at, trip.reload.ended_at
  end

  test "타임아웃 설정값을 단축하면 더 최근 trip도 종료된다" do
    # 1분 전 GPS: 기본 10분 타임아웃으로는 생존
    TripAutoTerminatorJob.perform_now
    assert_nil trips(:one_active).reload.ended_at

    # 같은 trip이 30초 타임아웃에서는 stale로 판정된다
    TripAutoTerminatorJob.perform_now(timeout: 30.seconds)
    assert_not_nil trips(:one_active).reload.ended_at
  end
end
