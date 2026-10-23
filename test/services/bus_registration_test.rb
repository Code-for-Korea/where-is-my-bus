require "test_helper"

class BusRegistrationTest < ActiveSupport::TestCase
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  setup do
    stub_traccar_credentials(TraccarDeviceSync, TraccarDeviceGroup)
  end

  test "create saves the bus and creates its Traccar device with the generated unique id" do
    create = stub_request(:post, "http://traccar.test/api/devices")
      .with { |req| JSON.parse(req.body).values_at("name") == [ "경남70가0001" ] && JSON.parse(req.body)["uniqueId"].match?(/\A\h{12}\z/) }
      .to_return(status: 200, body: { id: 66 }.to_json, headers: JSON_HEADERS)

    result = BusRegistration.create(license_plate: "경남70가0001")

    assert result.success?
    assert_equal 66, result.record.reload.traccar_device_id
    assert_requested create
  end

  test "create rolls back the bus when Traccar fails" do
    stub_request(:post, "http://traccar.test/api/devices").to_return(status: 500, body: "boom")

    assert_no_difference -> { Bus.count } do
      result = BusRegistration.create(license_plate: "경남70가0001")

      assert result.failure?
      assert result.record.new_record?
    end
  end

  test "create rejects a duplicate license plate without calling Traccar" do
    result = BusRegistration.create(license_plate: buses(:one).license_plate)

    assert result.failure?
    assert_not_requested :post, "http://traccar.test/api/devices"
  end

  test "destroy leaves the Traccar device alone when the bus has trips" do
    result = BusRegistration.destroy(buses(:one))

    assert result.failure?
    assert Bus.exists?(buses(:one).id)
    assert_not_requested :delete, %r{traccar.test/api/devices}
  end

  test "destroy removes a bus without trips and deletes its Traccar device" do
    bus = Bus.create!(license_plate: "경남70가0002", traccar_device_id: 777)
    delete = stub_request(:delete, "http://traccar.test/api/devices/777").to_return(status: 204, body: "")

    result = BusRegistration.destroy(bus)

    assert result.success?
    assert_not Bus.exists?(bus.id)
    assert_requested delete
  end

  test "create with a route moves the new device into the route's group" do
    stub_request(:post, "http://traccar.test/api/devices").to_return(status: 200, body: { id: 66 }.to_json, headers: JSON_HEADERS)
    move = stub_device_group_move(66, to_group_id: routes(:one).traccar_group_id)

    result = BusRegistration.create(license_plate: "경남70가0001", route_id: routes(:one).id)

    assert result.success?
    assert_requested move
  end

  test "create without a route leaves the device out of every group" do
    stub_request(:post, "http://traccar.test/api/devices").to_return(status: 200, body: { id: 66 }.to_json, headers: JSON_HEADERS)

    BusRegistration.create(license_plate: "경남70가0001")

    assert_not_requested :get, %r{/api/devices/66}
  end

  test "changing the route rolls back when the group cannot be moved" do
    bus = buses(:two)
    stub_device_update(bus.traccar_device_id)
    stub_request(:get, "http://traccar.test/api/devices/#{bus.traccar_device_id}").to_return(status: 500, body: "boom")

    result = BusRegistration.update(bus, route_id: routes(:one).id)

    assert result.failure?
    assert_match(/Traccar에서 차량을 노선에 배정하지 못했습니다/, result.error)
    assert_equal routes(:two), bus.reload.route
  end

  test "a running bus cannot be reassigned and Traccar is not called" do
    result = BusRegistration.update(buses(:one), route_id: routes(:two).id)

    assert result.failure?
    assert_match(/운행 중에는 바꿀 수 없습니다/, result.error)
    assert_not_requested :any, %r{traccar.test}
  end

  test "a resync of an assigned bus re-puts it in its group to repair drift" do
    bus = buses(:two)
    stub_device_update(bus.traccar_device_id)
    move = stub_device_group_move(bus.traccar_device_id, to_group_id: routes(:two).traccar_group_id)

    assert BusRegistration.update(bus, {}).success?
    assert_requested move
  end
end
