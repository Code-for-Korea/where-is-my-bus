require "test_helper"

class RouteBusTest < ActiveSupport::TestCase
  test "valid with a route and a bus" do
    route_bus = RouteBus.new(route: routes(:one), bus: buses(:one))
    assert route_bus.valid?
  end

  test "invalid without a route" do
    route_bus = RouteBus.new(bus: buses(:one))
    assert_not route_bus.valid?
  end

  test "invalid without a bus" do
    route_bus = RouteBus.new(route: routes(:one))
    assert_not route_bus.valid?
  end

  test "invalid when the same bus is assigned to the same route twice" do
    RouteBus.create!(route: routes(:one), bus: buses(:one))
    duplicate = RouteBus.new(route: routes(:one), bus: buses(:one))

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:bus_id, :taken)
  end

  test "allows the same bus assigned to different routes" do
    RouteBus.create!(route: routes(:one), bus: buses(:one))
    other_route = RouteBus.new(route: routes(:two), bus: buses(:one))

    assert other_route.valid?
  end

  test "allows different buses assigned to the same route" do
    RouteBus.create!(route: routes(:one), bus: buses(:one))
    other_bus = RouteBus.new(route: routes(:one), bus: buses(:two))

    assert other_bus.valid?
  end
end
