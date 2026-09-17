require "test_helper"

class TraccarGroupMembershipTest < ActiveSupport::TestCase
  setup do
    TraccarGroupMembership.stub_credentials(base_url: "http://traccar.test", email: "admin@test.com", password: "secret")
    TraccarGroupSync.stub_credentials(base_url: "http://traccar.test", email: "admin@test.com", password: "secret")

    @route = routes(:one)
    @route.update!(traccar_group_id: 7)
    @bus = buses(:one)
    @bus.update!(traccar_device_id: 99)
    @route_bus = RouteBus.create!(route: @route, bus: @bus)
  end

  test "add skips when bus has no traccar_device_id" do
    @bus.update!(traccar_device_id: nil)

    result = TraccarGroupMembership.add(@route_bus)

    assert result.success
    assert_not_requested :get, "http://traccar.test/api/devices/99"
  end

  test "add fetches the device, updates groupId, and PUTs it back" do
    stub_request(:get, "http://traccar.test/api/devices/99")
      .to_return(status: 200, body: { id: 99, name: "bus-99", uniqueId: "abc", groupId: 0 }.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:put, "http://traccar.test/api/devices/99")
      .with(body: { id: 99, name: "bus-99", uniqueId: "abc", groupId: 7 }.to_json)
      .to_return(status: 200, body: "", headers: {})

    result = TraccarGroupMembership.add(@route_bus)

    assert result.success
  end

  test "add creates the route's group first when it is missing, then links the device" do
    @route.update!(traccar_group_id: nil)
    stub_request(:post, "http://traccar.test/api/groups")
      .to_return(status: 200, body: { id: 55 }.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "http://traccar.test/api/devices/99")
      .to_return(status: 200, body: { id: 99, name: "bus-99", uniqueId: "abc", groupId: 0 }.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:put, "http://traccar.test/api/devices/99")
      .with(body: { id: 99, name: "bus-99", uniqueId: "abc", groupId: 55 }.to_json)
      .to_return(status: 200, body: "", headers: {})

    result = TraccarGroupMembership.add(@route_bus)

    assert result.success
    assert_equal 55, @route.reload.traccar_group_id
  end

  test "add returns the group sync failure result when group creation fails" do
    @route.update!(traccar_group_id: nil)
    stub_request(:post, "http://traccar.test/api/groups").to_return(status: 500, body: "boom")

    result = TraccarGroupMembership.add(@route_bus)

    assert result.failure?
    assert_not_requested :get, "http://traccar.test/api/devices/99"
  end

  test "add returns a failure result without raising when the API call fails" do
    stub_request(:get, "http://traccar.test/api/devices/99").to_return(status: 500, body: "boom")

    result = TraccarGroupMembership.add(@route_bus)

    assert result.failure?
  end

  test "remove skips when bus has no traccar_device_id" do
    @bus.update!(traccar_device_id: nil)

    result = TraccarGroupMembership.remove(@route_bus)

    assert result.success
    assert_not_requested :get, "http://traccar.test/api/devices/99"
  end

  test "remove fetches the device and PUTs groupId 0" do
    stub_request(:get, "http://traccar.test/api/devices/99")
      .to_return(status: 200, body: { id: 99, name: "bus-99", uniqueId: "abc", groupId: 7 }.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:put, "http://traccar.test/api/devices/99")
      .with(body: { id: 99, name: "bus-99", uniqueId: "abc", groupId: 0 }.to_json)
      .to_return(status: 200, body: "", headers: {})

    result = TraccarGroupMembership.remove(@route_bus)

    assert result.success
  end

  test "remove returns a failure result without raising when the API call fails" do
    stub_request(:get, "http://traccar.test/api/devices/99").to_return(status: 500, body: "boom")

    result = TraccarGroupMembership.remove(@route_bus)

    assert result.failure?
  end
end
