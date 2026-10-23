require "test_helper"

# 픽스처: 버스 one은 1번 노선에 배정되어 운행 중, 버스 two는 2번 노선에 배정되어 있고 운행 중이 아니다.
class TripStarterTest < ActiveSupport::TestCase
  test "starts a trip on the route the bus is assigned to" do
    result = TripStarter.call(bus: buses(:two))

    assert_equal :started, result.status
    assert_equal buses(:two), result.trip.bus
    assert_equal routes(:two), result.trip.route
    assert result.trip.active?
  end

  test "never calls Traccar — the device joined the route's group when the bus was assigned" do
    TripStarter.call(bus: buses(:two))

    assert_not_requested :any, %r{.}
  end

  test "starting again while a trip is running returns that trip" do
    result = TripStarter.call(bus: buses(:one))

    assert_equal :already_active, result.status
    assert_equal trips(:active_one), result.trip
  end

  test "a bus without an assigned route cannot start" do
    buses(:two).update_columns(route_id: nil)

    assert_no_difference -> { Trip.count } do
      result = TripStarter.call(bus: buses(:two).reload)

      assert_equal :no_route, result.status
      assert_nil result.trip
    end
  end

  test "a bus can start again after finishing" do
    trips(:active_one).finish!

    assert_equal :started, TripStarter.call(bus: buses(:one).reload).status
  end

  test "uses the route assigned now, not the one from an earlier trip" do
    buses(:two).update_columns(route_id: routes(:one).id)

    assert_equal routes(:one), TripStarter.call(bus: buses(:two).reload).trip.route
  end
end
