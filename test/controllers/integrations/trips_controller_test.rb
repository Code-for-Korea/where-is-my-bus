require "test_helper"

class Integrations::TripsControllerTest < ActionDispatch::IntegrationTest
  test "start begins a trip on the route the bus is assigned to" do
    bus = buses(:two)

    assert_difference -> { Trip.count }, 1 do
      post integrations_traccar_trips_start_path, params: { deviceId: bus.traccar_unique_id }
    end

    assert_response :ok
    assert_equal routes(:two).id, response.parsed_body.dig("trip", "routeId")
    assert_equal "2번 노선", response.parsed_body.dig("trip", "routeName")
    assert bus.reload.active_trip.present?
  end

  test "start ignores a route sent by the client — the assigned route wins" do
    post integrations_traccar_trips_start_path, params: { deviceId: buses(:two).traccar_unique_id, routeId: routes(:one).id }

    assert_equal routes(:two).id, response.parsed_body.dig("trip", "routeId")
  end

  test "start is idempotent while a trip is running" do
    assert_no_difference -> { Trip.count } do
      post integrations_traccar_trips_start_path, params: { deviceId: buses(:one).traccar_unique_id }
    end

    assert_response :ok
    assert_equal trips(:active_one).id, response.parsed_body.dig("trip", "id")
  end

  test "start answers 422 when the bus has no assigned route" do
    buses(:two).update_columns(route_id: nil)

    assert_no_difference -> { Trip.count } do
      post integrations_traccar_trips_start_path, params: { deviceId: buses(:two).traccar_unique_id }
    end

    assert_response :unprocessable_entity
    assert_equal "no_route_assigned", response.parsed_body["error"]
  end

  test "start answers 404 for an unknown device" do
    post integrations_traccar_trips_start_path, params: { deviceId: "nobody" }

    assert_response :not_found
    assert_equal "unknown_device", response.parsed_body["error"]
  end

  test "start never calls Traccar" do
    post integrations_traccar_trips_start_path, params: { deviceId: buses(:two).traccar_unique_id }

    assert_not_requested :any, %r{.}
  end

  test "end finishes the running trip" do
    bus = buses(:one)

    post integrations_traccar_trips_end_path, params: { deviceId: bus.traccar_unique_id }

    assert_response :ok
    assert_equal({ "ended" => true }, response.parsed_body)
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
