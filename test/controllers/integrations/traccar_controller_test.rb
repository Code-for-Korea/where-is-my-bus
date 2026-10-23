require "test_helper"

class Integrations::TraccarControllerTest < ActionDispatch::IntegrationTest
  test "register returns the device id for a valid pin and consumes the pin" do
    bus = buses(:one)

    post integrations_traccar_register_path, params: { pin: bus.pin }

    assert_response :ok
    assert_equal bus.traccar_unique_id, response.parsed_body["deviceId"]
    assert response.parsed_body["traccarServerUrl"].present?
    assert_not_nil bus.reload.pin_registered_at
  end

  test "register rejects an unknown pin" do
    post integrations_traccar_register_path, params: { pin: "000000" }

    assert_response :unauthorized
    assert_equal "invalid_pin", response.parsed_body["error"]
  end

  test "register rejects a pin that was already used" do
    buses(:one).update!(pin_registered_at: Time.current)

    post integrations_traccar_register_path, params: { pin: buses(:one).pin }

    assert_response :conflict
    assert_equal "pin_already_used", response.parsed_body["error"]
  end

  test "register works again with a regenerated pin" do
    bus = buses(:one)
    bus.update!(pin_registered_at: Time.current)
    bus.regenerate_pin!

    post integrations_traccar_register_path, params: { pin: bus.pin }

    assert_response :ok
  end

  test "register also returns the assigned route so the app can show it" do
    post integrations_traccar_register_path, params: { pin: buses(:one).pin }

    body = response.parsed_body
    assert_equal "1", body["busNumber"]
    assert_equal "경남70가1234", body["licensePlate"]
    assert_equal "1번 노선", body.dig("route", "name")
    assert_equal %w[고성터미널 고성시장 고성병원], body.dig("route", "stops").map { |s| s["name"] }
  end

  test "register reports a null route for a bus that has no assignment yet" do
    buses(:one).update_columns(route_id: nil)

    post integrations_traccar_register_path, params: { pin: buses(:one).pin }

    assert_response :ok
    assert_nil response.parsed_body["route"]
  end

  test "bus returns the assigned route with its stops in order, and the running trip" do
    get integrations_traccar_bus_path, params: { deviceId: buses(:one).traccar_unique_id }

    assert_response :ok
    body = response.parsed_body
    assert_equal "1", body["busNumber"]
    assert_equal routes(:one).id, body.dig("route", "id")
    assert_equal %w[고성터미널 고성시장 고성병원], body.dig("route", "stops").map { |s| s["name"] }
    assert_in_delta 34.9731, body.dig("route", "stops").first["lat"], 1e-6
    assert_equal trips(:active_one).id, body.dig("activeTrip", "id")
  end

  test "bus reports no active trip for a bus that is not running" do
    get integrations_traccar_bus_path, params: { deviceId: buses(:two).traccar_unique_id }

    assert_response :ok
    assert_nil response.parsed_body["activeTrip"]
    assert_equal "2번 노선", response.parsed_body.dig("route", "name")
  end

  test "bus returns a null route when nothing is assigned" do
    buses(:two).update_columns(route_id: nil)

    get integrations_traccar_bus_path, params: { deviceId: buses(:two).traccar_unique_id }

    assert_response :ok
    assert_nil response.parsed_body["route"]
  end

  test "bus returns 404 for an unknown device" do
    get integrations_traccar_bus_path, params: { deviceId: "nobody" }

    assert_response :not_found
    assert_equal "unknown_device", response.parsed_body["error"]
  end
end
