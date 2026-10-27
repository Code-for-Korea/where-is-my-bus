require "test_helper"

class TraccarDeviceGroupTest < ActiveSupport::TestCase
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  setup do
    TraccarDeviceGroup.stub_credentials(base_url: "http://traccar.test", email: "admin@test.com", password: "secret")
    @bus = buses(:one)
    @route = routes(:two)
  end

  def stub_device(group_id:)
    stub_request(:get, "http://traccar.test/api/devices/#{@bus.traccar_device_id}")
      .to_return(status: 200, headers: JSON_HEADERS,
                 body: { id: @bus.traccar_device_id, name: "bus", uniqueId: "abc", groupId: group_id }.to_json)
  end

  test "assign fetches the device and PUTs it back with the route's groupId" do
    stub_device(group_id: 0)
    put = stub_request(:put, "http://traccar.test/api/devices/#{@bus.traccar_device_id}")
      .with(body: { id: @bus.traccar_device_id, name: "bus", uniqueId: "abc", groupId: @route.traccar_group_id }.to_json)
      .to_return(status: 200, body: "")

    assert TraccarDeviceGroup.assign(@bus, @route).success
    assert_requested put
  end

  test "assign overwrites the previous route's group" do
    stub_device(group_id: routes(:one).traccar_group_id)
    put = stub_request(:put, "http://traccar.test/api/devices/#{@bus.traccar_device_id}")
      .with(body: hash_including(groupId: @route.traccar_group_id))
      .to_return(status: 200, body: "")

    assert TraccarDeviceGroup.assign(@bus, @route).success
    assert_requested put
  end

  test "assign fails without calling Traccar when the bus has no device" do
    @bus.update!(traccar_device_id: nil)

    assert TraccarDeviceGroup.assign(@bus, @route).failure?
    assert_not_requested :get, %r{traccar.test/api/devices}
  end

  test "assign fails without calling Traccar when the route has no group" do
    @route.update!(traccar_group_id: nil)

    assert TraccarDeviceGroup.assign(@bus, @route).failure?
    assert_not_requested :get, %r{traccar.test/api/devices}
  end

  test "assign returns a failure result without raising when the API call fails" do
    stub_request(:get, "http://traccar.test/api/devices/#{@bus.traccar_device_id}").to_return(status: 500, body: "boom")

    assert TraccarDeviceGroup.assign(@bus, @route).failure?
  end

  test "clear PUTs the device back with groupId 0" do
    stub_device(group_id: @route.traccar_group_id)
    put = stub_request(:put, "http://traccar.test/api/devices/#{@bus.traccar_device_id}")
      .with(body: hash_including(groupId: 0))
      .to_return(status: 200, body: "")

    assert TraccarDeviceGroup.clear(@bus).success
    assert_requested put
  end

  test "clear skips when the bus has no device" do
    @bus.update!(traccar_device_id: nil)

    assert TraccarDeviceGroup.clear(@bus).success
    assert_not_requested :get, %r{traccar.test/api/devices}
  end

  test "clear returns a failure result without raising when the API call fails" do
    stub_request(:get, "http://traccar.test/api/devices/#{@bus.traccar_device_id}").to_return(status: 500, body: "boom")

    assert TraccarDeviceGroup.clear(@bus).failure?
  end
end
