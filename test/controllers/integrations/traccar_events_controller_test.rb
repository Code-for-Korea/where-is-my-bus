require "test_helper"

class Integrations::TraccarEventsControllerTest < ActionDispatch::IntegrationTest
  INGEST_HEADERS = { "X-Ingest-Token" => "dev-traccar-token" }.freeze

  test "records a geofence enter event as a stop visit" do
    assert_difference -> { StopVisit.count }, 1 do
      post integrations_traccar_events_path, params: traccar_event(geofence_id: 203), headers: INGEST_HEADERS, as: :json
    end

    assert_response :ok
    assert_equal "recorded", response.parsed_body["status"]
  end

  test "acks ignored events with 200 and the reason so Traccar does not retry" do
    post integrations_traccar_events_path, params: traccar_event(unique_id: "nobody"), headers: INGEST_HEADERS, as: :json

    assert_response :ok
    assert_equal({ "status" => "ignored", "reason" => "unknown_device" }, response.parsed_body)
  end

  test "acks other Traccar event types without recording" do
    assert_no_difference -> { StopVisit.count } do
      post integrations_traccar_events_path, params: traccar_event(type: "deviceOnline"), headers: INGEST_HEADERS, as: :json
    end

    assert_response :ok
    assert_equal "unsupported_type", response.parsed_body["reason"]
  end

  test "rejects a request without the ingest token" do
    assert_no_difference -> { StopVisit.count } do
      post integrations_traccar_events_path, params: traccar_event(geofence_id: 203), as: :json
    end

    assert_response :unauthorized
  end

  test "rejects a request with a wrong ingest token" do
    post integrations_traccar_events_path, params: traccar_event, headers: { "X-Ingest-Token" => "wrong" }, as: :json

    assert_response :unauthorized
  end
end
