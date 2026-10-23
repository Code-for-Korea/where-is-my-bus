require "test_helper"

class Integrations::TripsControllerTest < ActionDispatch::IntegrationTest
  setup { stub_traccar_credentials(TraccarDeviceGroup) }

  test "start begins a trip for the chosen route" do
    bus = buses(:two)
    stub_device_group_move(bus.traccar_device_id, to_group_id: routes(:two).traccar_group_id)

    assert_difference -> { Trip.count }, 1 do
      post integrations_traccar_trips_start_path, params: { deviceId: bus.traccar_unique_id, routeId: routes(:two).id }
    end

    assert_response :ok
    assert_equal routes(:two).id, response.parsed_body.dig("trip", "routeId")
    assert_equal "2번 노선", response.parsed_body.dig("trip", "routeName")
    assert bus.reload.active_trip.present?
  end

  test "start answers 502 and creates nothing when Traccar fails" do
    bus = buses(:two)
    stub_request(:get, "#{TRACCAR_API}/api/devices/#{bus.traccar_device_id}").to_return(status: 500, body: "boom")

    assert_no_difference -> { Trip.count } do
      post integrations_traccar_trips_start_path, params: { deviceId: bus.traccar_unique_id, routeId: routes(:two).id }
    end

    assert_response :bad_gateway
    assert_equal "traccar_unavailable", response.parsed_body["error"]
  end

  test "start is idempotent for the route that is already running" do
    assert_no_difference -> { Trip.count } do
      post integrations_traccar_trips_start_path, params: { deviceId: buses(:one).traccar_unique_id, routeId: routes(:one).id }
    end

    assert_response :ok
    assert_equal trips(:active_one).id, response.parsed_body.dig("trip", "id")
  end

  test "start answers 409 with the running trip when another route is running" do
    post integrations_traccar_trips_start_path, params: { deviceId: buses(:one).traccar_unique_id, routeId: routes(:two).id }

    assert_response :conflict
    assert_equal "trip_already_active", response.parsed_body["error"]
    assert_equal routes(:one).id, response.parsed_body.dig("trip", "routeId")
  end

  test "start answers 404 for an unknown route or device" do
    post integrations_traccar_trips_start_path, params: { deviceId: buses(:two).traccar_unique_id, routeId: 0 }
    assert_response :not_found
    assert_equal "unknown_route", response.parsed_body["error"]

    post integrations_traccar_trips_start_path, params: { deviceId: "nobody", routeId: routes(:one).id }
    assert_response :not_found
    assert_equal "unknown_device", response.parsed_body["error"]
  end

  test "end finishes the running trip" do
    bus = buses(:one)
    stub_device_group_move(bus.traccar_device_id, to_group_id: 0)

    post integrations_traccar_trips_end_path, params: { deviceId: bus.traccar_unique_id }

    assert_response :ok
    assert_equal({ "ended" => true }, response.parsed_body)
    assert_nil bus.reload.active_trip
  end

  test "end succeeds with a warning when Traccar cannot clear the group" do
    bus = buses(:one)
    stub_request(:get, "#{TRACCAR_API}/api/devices/#{bus.traccar_device_id}").to_return(status: 500, body: "boom")

    post integrations_traccar_trips_end_path, params: { deviceId: bus.traccar_unique_id }

    assert_response :ok
    assert_equal({ "ended" => true, "warning" => "group_clear_failed" }, response.parsed_body)
    assert_nil bus.reload.active_trip
  end

  test "end is idempotent when no trip is running" do
    post integrations_traccar_trips_end_path, params: { deviceId: buses(:two).traccar_unique_id }

    assert_response :ok
    assert_equal({ "ended" => false }, response.parsed_body)
  end

  test "end answers 404 for an unknown device" do
    post integrations_traccar_trips_end_path, params: { deviceId: "nobody" }

    assert_response :not_found
  end
end
