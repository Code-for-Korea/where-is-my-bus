require "test_helper"

class TraccarDeviceSyncTest < ActiveSupport::TestCase
  setup do
    TraccarDeviceSync.stub_credentials(base_url: "http://traccar.test", email: "admin@test.com", password: "secret")
    @bus = buses(:one)
    @bus.update_columns(traccar_device_id: nil)
  end

  test "creates a device when bus has no traccar_device_id" do
    stub_request(:post, "http://traccar.test/api/devices")
      .with(body: { name: @bus.license_plate, uniqueId: @bus.traccar_unique_id }.to_json)
      .to_return(status: 200, body: { id: 99, name: @bus.license_plate, uniqueId: @bus.traccar_unique_id }.to_json, headers: { "Content-Type" => "application/json" })

    result = TraccarDeviceSync.call(@bus)

    assert result.success
    assert_equal 99, @bus.reload.traccar_device_id
  end

  test "updates the device when bus already has a traccar_device_id" do
    @bus.update_columns(traccar_device_id: 99)
    stub_request(:put, "http://traccar.test/api/devices/99")
      .with(body: { id: 99, name: @bus.license_plate, uniqueId: @bus.traccar_unique_id }.to_json)
      .to_return(status: 200, body: "", headers: {})

    result = TraccarDeviceSync.call(@bus)

    assert result.success
    assert_equal 99, @bus.reload.traccar_device_id
  end

  test "returns a failure result without raising when the API call fails" do
    stub_request(:post, "http://traccar.test/api/devices").to_return(status: 500, body: "boom")

    result = TraccarDeviceSync.call(@bus)

    assert result.failure?
    assert_nil @bus.reload.traccar_device_id
  end

  test "destroy skips when bus has no traccar_device_id" do
    result = TraccarDeviceSync.destroy(@bus)

    assert result.success
  end

  test "destroy deletes the device when bus has a traccar_device_id" do
    @bus.update_columns(traccar_device_id: 99)
    stub_request(:delete, "http://traccar.test/api/devices/99").to_return(status: 204, body: "")

    result = TraccarDeviceSync.destroy(@bus)

    assert result.success
  end

  test "destroy returns a failure result without raising when the API call fails" do
    @bus.update_columns(traccar_device_id: 99)
    stub_request(:delete, "http://traccar.test/api/devices/99").to_return(status: 500, body: "boom")

    result = TraccarDeviceSync.destroy(@bus)

    assert result.failure?
  end

  test "returns a failure result without raising when credentials are not configured" do
    TraccarDeviceSync.stub_credentials(base_url: nil, email: nil, password: nil)

    result = TraccarDeviceSync.call(@bus)

    assert result.failure?
    assert_nil @bus.reload.traccar_device_id
  ensure
    TraccarDeviceSync.stub_credentials(base_url: "http://traccar.test", email: "admin@test.com", password: "secret")
  end
end
