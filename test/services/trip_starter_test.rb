require "test_helper"

# 픽스처: 버스 one은 1번 노선을 운행 중, 버스 two는 운행 중이 아님 (device 302, 2번 노선 group 102).
class TripStarterTest < ActiveSupport::TestCase
  setup { stub_traccar_credentials(TraccarDeviceGroup) }

  test "starts a trip and moves the device into the route's group" do
    move = stub_device_group_move(buses(:two).traccar_device_id, to_group_id: routes(:two).traccar_group_id)

    result = TripStarter.call(bus: buses(:two), route: routes(:two))

    assert_equal :started, result.status
    assert_equal buses(:two), result.trip.bus
    assert_equal routes(:two), result.trip.route
    assert result.trip.active?
    assert_requested move
  end

  test "rolls back the trip when Traccar fails" do
    stub_request(:get, "#{TRACCAR_API}/api/devices/#{buses(:two).traccar_device_id}").to_return(status: 500, body: "boom")

    assert_no_difference -> { Trip.count } do
      result = TripStarter.call(bus: buses(:two), route: routes(:two))

      assert_equal :traccar_failed, result.status
      assert_match(/group 이동 실패/, result.error)
    end
    assert_nil buses(:two).reload.active_trip
  end

  test "fails without a trip when the bus has no Traccar device" do
    buses(:two).update!(traccar_device_id: nil)

    assert_no_difference -> { Trip.count } do
      assert_equal :traccar_failed, TripStarter.call(bus: buses(:two), route: routes(:two)).status
    end
  end

  test "starting the same route again returns the running trip without touching Traccar" do
    result = TripStarter.call(bus: buses(:one), route: routes(:one))

    assert_equal :already_active, result.status
    assert_equal trips(:active_one), result.trip
    assert_not_requested :get, %r{traccar.test/api/devices}
  end

  test "starting a different route while a trip is running is a conflict" do
    assert_no_difference -> { Trip.count } do
      result = TripStarter.call(bus: buses(:one), route: routes(:two))

      assert_equal :conflict, result.status
      assert_equal trips(:active_one), result.trip
    end
  end

  test "a bus can start again after finishing" do
    trips(:active_one).finish!
    stub_device_group_move(buses(:one).traccar_device_id, to_group_id: routes(:two).traccar_group_id)

    assert_equal :started, TripStarter.call(bus: buses(:one).reload, route: routes(:two)).status
  end
end
