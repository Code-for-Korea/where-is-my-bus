require "test_helper"

class BusTest < ActiveSupport::TestCase
  test "routes returns routes assigned through route_buses" do
    bus = buses(:one)
    RouteBus.create!(route: routes(:one), bus: bus)
    RouteBus.create!(route: routes(:two), bus: bus)

    assert_equal [ routes(:one), routes(:two) ].sort_by(&:id), bus.routes.sort_by(&:id)
  end

  test "destroying a bus destroys its route_buses but not the routes" do
    bus = buses(:one)
    route = routes(:one)
    route_bus = RouteBus.create!(route: route, bus: bus)

    bus.destroy

    assert_not RouteBus.exists?(route_bus.id)
    assert Route.exists?(route.id)
  end
end
