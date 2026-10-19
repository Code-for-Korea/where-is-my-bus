require "test_helper"

class PositionIngestorTest < ActiveSupport::TestCase
  setup do
    @bus = buses(:one)
    @bus.update!(traccar_unique_id: "test-device-1")
    # fixture(buses(:one))에는 활성 trip이 매여 있어 "생성 전 0건" 단언이 성립하지 않는다 — 격리를 위해 제거
    @bus.trips.destroy_all
  end

  test "creates trip, gps log, current position and position history for a valid Traccar forwarding payload" do
    recorded_at = Time.zone.parse("2026-10-18T12:00:00Z")

    result = PositionIngestor.call(traccar_payload(fix_time: recorded_at.iso8601), source: :traccar)

    assert result.success?, result.message
    assert_equal @bus, result.bus
    assert result.trip.persisted?
    assert_nil result.trip.ended_at

    assert_equal 34.123456.to_d, result.gps_log.lat
    assert_equal 128.123456.to_d, result.gps_log.lng
    assert_equal recorded_at.to_i, result.gps_log.recorded_at.to_i

    current = @bus.reload.current_position
    assert current
    assert_equal 34.123456.to_d, current.lat
    assert_equal 128.123456.to_d, current.lng
    assert_equal 10.5, current.speed
    assert_equal 90.0, current.bearing
    assert_equal 5.0, current.accuracy
    assert_equal 80, current.battery
    assert_equal recorded_at.to_i, current.recorded_at.to_i

    history = @bus.position_histories.last
    assert history
    assert_equal 34.123456.to_d, history.lat
    assert_equal 80, history.battery
  end

  test "creates records for a valid OsmAnd payload" do
    timestamp = 1_760_788_800
    recorded_at = Time.zone.at(timestamp)

    result = PositionIngestor.call(osmand_payload(timestamp: timestamp), source: :osmand)

    assert result.success?, result.message
    current = @bus.reload.current_position
    assert current
    assert_equal 34.123456.to_d, current.lat
    assert_equal recorded_at.to_i, current.recorded_at.to_i
    assert_equal 1, @bus.position_histories.count
    assert_equal 1, @bus.trips.count
  end

  test "reuses active trip instead of creating a new one" do
    existing_trip = @bus.trips.create!(started_at: 10.minutes.ago)

    result = PositionIngestor.call(traccar_payload, source: :traccar)

    assert result.success?
    assert_equal existing_trip.id, result.trip.id
  end

  test "recovers from concurrent current position insert (RecordNotUnique race)" do
    older_time = 2.minutes.ago
    newer_time = 1.minute.ago
    PositionIngestor.call(traccar_payload(lat: 34.0, lng: 128.0, fix_time: older_time.iso8601), source: :traccar)

    # race: find_or_initialize_by가 이미 존재하는 row를 보지 못한(다른 요청이 커밋 전인) 첫 조회를 흉내낸다
    CurrentPosition.singleton_class.alias_method(:__original_find_or_initialize_by, :find_or_initialize_by)
    CurrentPosition.define_singleton_method(:find_or_initialize_by) do |attributes|
      CurrentPosition.new(attributes)
    end

    result = PositionIngestor.call(traccar_payload(lat: 35.0, lng: 129.0, fix_time: newer_time.iso8601), source: :traccar)

    assert result.success?
    current = @bus.reload.current_position
    assert_equal 35.0.to_d, current.lat
    assert_equal 129.0.to_d, current.lng
    assert_equal newer_time.to_i, current.recorded_at.to_i
  ensure
    CurrentPosition.singleton_class.send(:remove_method, :find_or_initialize_by)
    CurrentPosition.singleton_class.send(:alias_method, :find_or_initialize_by, :__original_find_or_initialize_by)
  end

  test "blocks duplicate active trips via partial unique index" do
    @bus.trips.create!(started_at: 10.minutes.ago)

    assert_raises(ActiveRecord::RecordNotUnique) do
      @bus.trips.create!(started_at: 5.minutes.ago)
    end
  end

  test "returns skipped for unknown device" do
    result = PositionIngestor.call(traccar_payload(unique_id: "unknown-device"), source: :traccar)

    assert result.skipped?
    assert_equal :unknown_device, result.error
    assert_equal 0, @bus.reload.trips.count
    assert_nil @bus.current_position
    assert_equal 0, PositionHistory.count
  end

  test "returns skipped for missing coordinates" do
    result = PositionIngestor.call(traccar_payload(lat: nil, lng: nil), source: :traccar)

    assert result.skipped?
    assert_equal :missing_coordinates, result.error
    assert_equal 0, @bus.reload.trips.count
    assert_nil @bus.current_position
  end

  test "upserts current position and ignores older recorded_at (time reversal guard)" do
    newer_time = 1.minute.ago
    older_time = 2.minutes.ago

    PositionIngestor.call(traccar_payload(lat: 34.0, lng: 128.0, fix_time: newer_time.iso8601), source: :traccar)
    result = PositionIngestor.call(traccar_payload(lat: 35.0, lng: 129.0, fix_time: older_time.iso8601), source: :traccar)

    assert result.success?
    current = @bus.reload.current_position
    assert_equal 34.0.to_d, current.lat
    assert_equal 128.0.to_d, current.lng
    assert_equal newer_time.to_i, current.recorded_at.to_i
    assert_equal 2, @bus.position_histories.count
  end

  test "updates current position when recorded_at is equal" do
    time = 1.minute.ago

    PositionIngestor.call(traccar_payload(lat: 34.0, lng: 128.0, fix_time: time.iso8601), source: :traccar)
    result = PositionIngestor.call(traccar_payload(lat: 35.0, lng: 129.0, fix_time: time.iso8601), source: :traccar)

    assert result.success?
    current = @bus.reload.current_position
    assert_equal 35.0.to_d, current.lat
    assert_equal 129.0.to_d, current.lng
  end

  test "does not create StopEvent when stale GPS does not update current position" do
    RouteBus.create!(route: routes(:one), bus: @bus)
    newer_time = 1.minute.ago
    older_time = 30.minutes.ago

    # 정류장1 좌표로 최신 위치 수신 → CurrentPosition 갱신 + arrive 이벤트 생성
    PositionIngestor.call(traccar_payload(lat: 35.100000, lng: 128.100000, fix_time: newer_time.iso8601), source: :traccar)
    assert_equal 1, StopEvent.where(stop: stops(:one), event_type: "arrive").count

    # 30분 전 timestamp로 정류장3 좌표 재전송(stale) → CurrentPosition 미갱신, 가짜 이벤트 없음
    event_count = StopEvent.count
    result = PositionIngestor.call(traccar_payload(lat: 35.102000, lng: 128.102000, fix_time: older_time.iso8601), source: :traccar)

    assert result.success?, result.message
    assert_equal false, result.updated
    current = @bus.reload.current_position
    assert_equal 35.100000.to_d, current.lat
    assert_equal 128.100000.to_d, current.lng
    assert_equal newer_time.to_i, current.recorded_at.to_i
    assert_equal event_count, StopEvent.count
    assert_equal 0, StopEvent.where(stop: stops(:three)).count
  end

  test "parses epoch second timestamp" do
    timestamp = 1_760_788_800
    recorded_at = Time.zone.at(timestamp)

    result = PositionIngestor.call(osmand_payload(timestamp: timestamp), source: :osmand)

    assert result.success?
    assert_equal recorded_at.to_i, result.gps_log.recorded_at.to_i
  end

  test "parses epoch millisecond timestamp" do
    timestamp_ms = 1_760_788_800_000
    recorded_at = Time.zone.at(timestamp_ms / 1000.0)

    result = PositionIngestor.call(osmand_payload(timestamp: timestamp_ms), source: :osmand)

    assert result.success?
    assert_equal recorded_at.to_i, result.gps_log.recorded_at.to_i
  end

  private

  def traccar_payload(unique_id: @bus.traccar_unique_id, lat: 34.123456, lng: 128.123456,
                      speed: 10.5, course: 90.0, accuracy: 5.0, battery_level: 80, fix_time: "2026-10-18T12:00:00Z")
    {
      device: { uniqueId: unique_id },
      position: {
        latitude: lat,
        longitude: lng,
        speed: speed,
        course: course,
        accuracy: accuracy,
        batteryLevel: battery_level,
        fixTime: fix_time
      }.compact
    }
  end

  def osmand_payload(id: @bus.traccar_unique_id, lat: 34.123456, lon: 128.123456,
                     timestamp: 1_760_788_800, speed: 0.0, bearing: 0.0, accuracy: 5.0, batt: 87)
    {
      id: id,
      lat: lat,
      lon: lon,
      timestamp: timestamp,
      speed: speed,
      bearing: bearing,
      accuracy: accuracy,
      batt: batt
    }.compact
  end
end
