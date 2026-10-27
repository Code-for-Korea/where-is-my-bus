require "test_helper"

class RouteStopTest < ActiveSupport::TestCase
  test "sequence must be a positive integer" do
    route_stop = RouteStop.new(route: routes(:one), stop: stops(:school), sequence: 0)

    assert_not route_stop.valid?
    assert route_stop.errors.of_kind?(:sequence, :greater_than)
  end

  test "the same stop cannot be added to a route twice" do
    duplicate = RouteStop.new(route: routes(:one), stop: stops(:terminal), sequence: 9)

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:stop_id, :taken)
  end

  test "sequence must be unique within a route" do
    duplicate = RouteStop.new(route: routes(:one), stop: stops(:school), sequence: 1)

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:sequence, :taken)
  end

  test "the same sequence is allowed on different routes" do
    assert RouteStop.new(route: routes(:two), stop: stops(:market), sequence: 4).valid?
    assert RouteStop.new(route: routes(:one), stop: stops(:school), sequence: 4).valid?
  end
end
