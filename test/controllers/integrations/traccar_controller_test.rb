require "test_helper"

class Integrations::TraccarControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bus = buses(:one)
    @bus.update!(traccar_unique_id: "test-device-1")
    @bus.trips.destroy_all
  end

  test "positions returns 200 and ingests a valid traccar forwarding payload" do
    assert_difference -> { @bus.reload.trips.count } => 1,
                      -> { GpsLog.count } => 1,
                      -> { CurrentPosition.count } => 1,
                      -> { PositionHistory.count } => 1 do
      post integrations_traccar_positions_path, params: {
        device: { uniqueId: @bus.traccar_unique_id },
        position: {
          latitude: 34.123456,
          longitude: 128.123456,
          speed: 10.5,
          course: 90.0,
          accuracy: 5.0,
          batteryLevel: 80,
          deviceTime: "2026-10-18T12:00:00Z"
        }
      }, headers: { "X-Ingest-Token" => ingest_token }
    end

    assert_response :ok
  end

  test "positions returns 401 with bad token" do
    post integrations_traccar_positions_path, params: {
      device: { uniqueId: @bus.traccar_unique_id },
      position: { latitude: 34.0, longitude: 128.0 }
    }, headers: { "X-Ingest-Token" => "bad-token" }

    assert_response :unauthorized
  end

  test "positions returns 200 for unknown device" do
    post integrations_traccar_positions_path, params: {
      device: { uniqueId: "unknown-device" },
      position: { latitude: 34.0, longitude: 128.0 }
    }, headers: { "X-Ingest-Token" => ingest_token }

    assert_response :ok
  end

  test "positions returns 200 for missing coordinates" do
    post integrations_traccar_positions_path, params: {
      device: { uniqueId: @bus.traccar_unique_id },
      position: { latitude: nil, longitude: nil }
    }, headers: { "X-Ingest-Token" => ingest_token }

    assert_response :ok
  end

  test "positions accepts a JSON array batch payload" do
    payload = [
      { device: { uniqueId: @bus.traccar_unique_id },
        position: { latitude: 34.1, longitude: 128.1, fixTime: "2026-10-18T12:00:00Z" } },
      { device: { uniqueId: @bus.traccar_unique_id },
        position: { latitude: 34.2, longitude: 128.2, fixTime: "2026-10-18T12:00:01Z" } }
    ]

    assert_difference -> { @bus.reload.trips.count } => 1,
                      -> { GpsLog.count } => 2,
                      -> { CurrentPosition.count } => 1,
                      -> { PositionHistory.count } => 2 do
      post integrations_traccar_positions_path,
           params: payload.to_json,
           headers: { "CONTENT_TYPE" => "application/json", "X-Ingest-Token" => ingest_token }
    end

    assert_response :ok
  end

  private

  def ingest_token
    Rails.env.local? ? "dev-traccar-token" : "test-token"
  end
end
