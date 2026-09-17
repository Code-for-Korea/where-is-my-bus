require "test_helper"

class RouteTest < ActiveSupport::TestCase
  test "buses returns buses assigned through route_buses" do
    route = routes(:one)
    RouteBus.create!(route: route, bus: buses(:one))
    RouteBus.create!(route: route, bus: buses(:two))

    assert_equal [ buses(:one), buses(:two) ].sort_by(&:id), route.buses.sort_by(&:id)
  end

  test "destroying a route destroys its route_buses" do
    route = routes(:one)
    route_bus = RouteBus.create!(route: route, bus: buses(:one))

    route.destroy

    assert_not RouteBus.exists?(route_bus.id)
  end

  test "does not respond to the removed singular bus association" do
    assert_not routes(:one).respond_to?(:bus)
  end
end
