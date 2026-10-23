require "test_helper"

class TripFinisherTest < ActiveSupport::TestCase
  setup { stub_traccar_credentials(TraccarDeviceGroup) }

  test "ends the active trip and clears the device's group" do
    clear = stub_device_group_move(buses(:one).traccar_device_id, to_group_id: 0)

    result = TripFinisher.call(buses(:one))

    assert_equal trips(:active_one), result.trip
    assert_nil result.warning
    assert_not trips(:active_one).reload.active?
    assert_requested clear
  end

  test "still ends the trip when Traccar cannot clear the group" do
    stub_request(:get, "#{TRACCAR_API}/api/devices/#{buses(:one).traccar_device_id}").to_return(status: 500, body: "boom")

    result = TripFinisher.call(buses(:one))

    assert_equal :group_clear_failed, result.warning
    assert_not trips(:active_one).reload.active?
  end

  test "is a no-op when the bus has no active trip" do
    result = TripFinisher.call(buses(:two))

    assert_nil result.trip
    assert_nil result.warning
    assert_not_requested :get, %r{traccar.test/api/devices}
  end

  test "frees the bus to start another trip" do
    stub_device_group_move(buses(:one).traccar_device_id, to_group_id: 0)

    TripFinisher.call(buses(:one))

    assert_nil buses(:one).reload.active_trip
  end
end
