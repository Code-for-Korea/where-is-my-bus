require "test_helper"

# 픽스처: 버스 one은 1번 노선(터미널 → 시장 → 병원)을 운행 중이고, 시장 안에 있다(열린 방문 기록).
# 터미널은 이미 출발했고, 병원은 아직 방문 기록이 없다. 고등학교(204)는 1번 노선에 속하지 않는다.
class StopVisitRecorderTest < ActiveSupport::TestCase
  test "enter creates a visit at the stop with the event time and key" do
    at = 3.minutes.ago

    result = StopVisitRecorder.call(traccar_event(type: "geofenceEnter", id: 10, geofence_id: 203, at: at))

    assert result.recorded?
    visit = result.visit
    assert_equal stops(:hospital), visit.stop
    assert_equal trips(:active_one), visit.trip
    assert_in_delta at.to_f, visit.entered_at.to_f, 0.001
    assert_nil visit.exited_at
    assert_equal "10@#{at.utc.iso8601(3)}", visit.entered_event_id
  end

  test "exit closes the open visit of the same stop" do
    at = 1.minute.ago

    result = StopVisitRecorder.call(traccar_event(type: "geofenceExit", id: 11, geofence_id: 202, at: at))

    assert result.recorded?
    assert_equal stop_visits(:at_market), result.visit
    assert_in_delta at.to_f, result.visit.reload.exited_at.to_f, 0.001
    assert_equal "11@#{at.utc.iso8601(3)}", result.visit.exited_event_id
  end

  test "the same enter event delivered twice is recorded once" do
    payload = traccar_event(type: "geofenceEnter", id: 10, geofence_id: 203)

    assert StopVisitRecorder.call(payload).recorded?
    assert_no_difference -> { StopVisit.count } do
      result = StopVisitRecorder.call(payload)

      assert result.ignored?
      assert_equal :duplicate, result.reason
    end
  end

  test "the same exit event delivered twice is applied once" do
    payload = traccar_event(type: "geofenceExit", id: 11, geofence_id: 202)

    assert StopVisitRecorder.call(payload).recorded?
    result = StopVisitRecorder.call(payload)

    assert_equal :duplicate, result.reason
  end

  test "an event id reused after Traccar was reset is not mistaken for a duplicate" do
    StopVisitRecorder.call(traccar_event(type: "geofenceEnter", id: 1, geofence_id: 203, at: 4.minutes.ago))
    StopVisitRecorder.call(traccar_event(type: "geofenceExit", id: 2, geofence_id: 203, at: 3.minutes.ago))

    result = StopVisitRecorder.call(traccar_event(type: "geofenceEnter", id: 1, geofence_id: 203, at: 1.minute.ago))

    assert result.recorded?
  end

  test "entering again after leaving creates another visit" do
    StopVisitRecorder.call(traccar_event(type: "geofenceEnter", id: 10, geofence_id: 203, at: 4.minutes.ago))
    StopVisitRecorder.call(traccar_event(type: "geofenceExit", id: 11, geofence_id: 203, at: 3.minutes.ago))

    assert_difference -> { StopVisit.where(stop: stops(:hospital)).count }, 1 do
      assert StopVisitRecorder.call(traccar_event(type: "geofenceEnter", id: 12, geofence_id: 203, at: 1.minute.ago)).recorded?
    end
  end

  test "entering a stop that the bus has not left yet is ignored" do
    result = StopVisitRecorder.call(traccar_event(type: "geofenceEnter", id: 10, geofence_id: 202))

    assert_equal :already_inside, result.reason
  end

  test "an exit without an open visit is ignored" do
    result = StopVisitRecorder.call(traccar_event(type: "geofenceExit", id: 10, geofence_id: 203))

    assert_equal :no_open_visit, result.reason
  end

  test "other event types are ignored" do
    result = StopVisitRecorder.call(traccar_event(type: "deviceOnline"))

    assert_equal :unsupported_type, result.reason
  end

  test "an unknown device is ignored" do
    result = StopVisitRecorder.call(traccar_event(unique_id: "nobody"))

    assert_equal :unknown_device, result.reason
  end

  test "an unknown geofence is ignored" do
    result = StopVisitRecorder.call(traccar_event(geofence_id: 9999))

    assert_equal :unknown_geofence, result.reason
  end

  test "a bus without an active trip is ignored" do
    result = StopVisitRecorder.call(traccar_event(unique_id: buses(:two).traccar_unique_id))

    assert_equal :no_active_trip, result.reason
  end

  test "a stop that is not on the trip's route is ignored" do
    result = StopVisitRecorder.call(traccar_event(geofence_id: stops(:school).traccar_geofence_id))

    assert_equal :stop_not_on_route, result.reason
  end

  test "an event from before the trip started is ignored" do
    result = StopVisitRecorder.call(traccar_event(at: 2.hours.ago))

    assert_equal :before_trip_start, result.reason
  end

  test "an empty payload is ignored as an unsupported type" do
    assert_equal :unsupported_type, StopVisitRecorder.call({}).reason
  end

  test "a geofence event missing a required field is ignored as invalid" do
    [ [ :event, :id ], [ :event, :eventTime ], [ :event, :geofenceId ], [ :device, :uniqueId ] ].each do |parent, key|
      payload = traccar_event
      payload[parent].delete(key)

      assert_equal :invalid_payload, StopVisitRecorder.call(payload).reason, "missing #{parent}.#{key}"
    end
  end

  test "a geofence event with an unparseable time is ignored as invalid" do
    payload = traccar_event
    payload[:event][:eventTime] = "not a time"

    assert_equal :invalid_payload, StopVisitRecorder.call(payload).reason
  end

  # test/fixtures/files의 JSON은 traccar/traccar:6가 실제로 보낸 이벤트를 그대로 저장한 것이다.
  # 식별자와 시각만 픽스처 데이터에 맞게 바꿔서, 실제 필드 구성으로도 기록되는지 확인한다.
  test "records events in the exact shape Traccar really sends" do
    enter = real_event("traccar_geofence_enter", geofence_id: 203, at: 4.minutes.ago)
    exit_ = real_event("traccar_geofence_exit", geofence_id: 203, at: 2.minutes.ago)

    assert StopVisitRecorder.call(enter).recorded?
    result = StopVisitRecorder.call(exit_)

    assert result.recorded?
    assert_not result.visit.open?
    assert_equal stops(:hospital), result.visit.stop
  end

  test "accepts a payload with string keys as parsed from JSON" do
    payload = JSON.parse(traccar_event(geofence_id: 203).to_json)

    assert StopVisitRecorder.call(payload).recorded?
  end

  private

  def real_event(fixture_name, geofence_id:, at:)
    payload = JSON.parse(file_fixture("#{fixture_name}.json").read)
    payload["event"]["geofenceId"] = geofence_id
    payload["event"]["eventTime"] = at.utc.iso8601(3)
    payload["device"]["uniqueId"] = buses(:one).traccar_unique_id
    payload
  end
end
