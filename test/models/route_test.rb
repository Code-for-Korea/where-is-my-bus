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

  test "regions are the distinct regions of its stops, ordered by level then name" do
    route = Route.create!(name: "지역 혼합 노선")
    eup = Stop.create!(name: "울릉읍 정류장", lat: 37.48, lng: 130.9, region: regions(:ulleung_eup))
    [ stops(:terminal), eup, stops(:market) ].each.with_index(1) { |stop, i| route.route_stops.create!(stop: stop, sequence: i) }

    assert_equal [ regions(:goseong), regions(:ulleung_eup) ], route.regions.to_a
  end

  test "stops sharing a region do not duplicate it" do
    assert_equal [ regions(:goseong) ], routes(:one).regions.to_a
    assert_equal [ regions(:goseong) ], routes(:two).regions.to_a
  end

  test "regionless stops are skipped and routes without regions are empty" do
    mixed = Route.create!(name: "혼합 노선")
    mixed.route_stops.create!(stop: stops(:legacy), sequence: 1)
    mixed.route_stops.create!(stop: stops(:school), sequence: 2)
    only_legacy = Route.create!(name: "레거시 노선")
    only_legacy.route_stops.create!(stop: stops(:legacy), sequence: 1)
    empty = Route.create!(name: "빈 노선")

    assert_equal [ regions(:goseong) ], mixed.regions.to_a
    assert_empty only_legacy.regions
    assert_empty empty.regions
  end

  test "regions_by_route matches per-route regions" do
    mixed = Route.create!(name: "지역 혼합 노선")
    mixed.route_stops.create!(stop: Stop.create!(name: "파장동 정류장", lat: 37.3, lng: 127.0, region: regions(:pajang)), sequence: 1)
    mixed.route_stops.create!(stop: stops(:legacy), sequence: 2)
    mixed.route_stops.create!(stop: stops(:terminal), sequence: 3)
    empty = Route.create!(name: "빈 노선")
    all = Route.all.to_a

    batch = Route.regions_by_route(all)

    assert_equal all.map(&:id).sort, batch.keys.sort
    all.each { |route| assert_equal route.regions.to_a, batch[route.id], route.name }
    assert_empty batch[empty.id]
  end
end
