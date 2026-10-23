require "test_helper"

class StopTest < ActiveSupport::TestCase
  test "requires name and coordinates within range" do
    assert_not Stop.new(lat: 34.9, lng: 128.3).valid?
    assert_not Stop.new(name: "A", lng: 128.3).valid?
    assert_not Stop.new(name: "A", lat: 91, lng: 128.3).valid?
    assert_not Stop.new(name: "A", lat: 34.9, lng: 181).valid?
    assert Stop.new(name: "A", lat: 34.9, lng: 128.3).valid?
  end

  test "traccar_geofence_id must be unique when present" do
    duplicate = Stop.new(name: "A", lat: 34.9, lng: 128.3, traccar_geofence_id: stops(:terminal).traccar_geofence_id)

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:traccar_geofence_id, :taken)
  end

  test "a stop can belong to several routes" do
    assert_equal [ routes(:one), routes(:two) ].sort_by(&:id), stops(:hospital).routes.sort_by(&:id)
  end

  test "cannot be destroyed while it has visit records" do
    assert_not stops(:terminal).destroy
    assert Stop.exists?(stops(:terminal).id)
  end

  test "destroying a stop without visits removes its route_stops" do
    assert_difference -> { RouteStop.count }, -1 do
      stops(:school).destroy!
    end
  end
end
