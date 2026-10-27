require "test_helper"

class RouteTest < ActiveSupport::TestCase
  test "name must be present and unique" do
    assert_not Route.new(name: "").valid?

    duplicate = Route.new(name: routes(:one).name)
    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:name, :taken)
  end

  test "stops are returned in route sequence order" do
    assert_equal %w[고성터미널 고성시장 고성병원], routes(:one).stops.map(&:name)
    assert_equal %w[고성터미널 고성병원 고성고등학교], routes(:two).stops.map(&:name)
  end

  test "destroying a route removes its route_stops but keeps the stops" do
    route = Route.create!(name: "임시 노선")
    route.route_stops.create!(stop: stops(:school), sequence: 1)

    assert_difference -> { RouteStop.count }, -1 do
      assert_no_difference -> { Stop.count } do
        route.destroy
      end
    end
  end

  test "cannot be destroyed while it has trips" do
    assert_not routes(:one).destroy
    assert Route.exists?(routes(:one).id)
  end

  test "cannot be destroyed while buses are assigned to it" do
    route = Route.create!(name: "임시 노선")
    Bus.create!(license_plate: "경남70가0003", route: route)

    assert_not route.destroy
    assert_includes route.errors[:base].join, "배정된 차량"
  end
end
