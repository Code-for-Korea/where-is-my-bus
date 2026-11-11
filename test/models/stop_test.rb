require "test_helper"

class StopTest < ActiveSupport::TestCase
  test "requires name and coordinates within range" do
    assert_not Stop.new(lat: 34.9, lng: 128.3).valid?
    assert_not Stop.new(name: "A", lng: 128.3).valid?
    assert_not Stop.new(name: "A", lat: 91, lng: 128.3).valid?
    assert_not Stop.new(name: "A", lat: 34.9, lng: 181).valid?
    assert Stop.new(name: "A", lat: 34.9, lng: 128.3, region: regions(:goseong)).valid?
  end

  test "traccar_geofence_id must be unique when present" do
    duplicate = Stop.new(name: "A", lat: 34.9, lng: 128.3, traccar_geofence_id: stops(:terminal).traccar_geofence_id,
                             region: regions(:goseong))

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

  test "a new stop requires a region of at least sigungu level" do
    stop = Stop.new(name: "A", lat: 34.9, lng: 128.3)
    assert_not stop.valid?
    assert stop.errors.of_kind?(:region, :blank)

    stop.region = regions(:gyeongnam)
    assert_not stop.valid?
    assert stop.errors[:region].any?

    [ :goseong, :ulleung_eup, :bangok ].each do |label|
      stop.region = regions(label)
      assert stop.valid?, "#{label} should be valid"
    end
  end

  test "a legacy stop without a region can still be saved when only other fields change" do
    stop = stops(:legacy)
    assert_nil stop.region_id

    stop.name = "이름만 변경"

    assert stop.valid?
    assert stop.save
  end

  test "changing the region of an existing stop validates the new region" do
    stop = stops(:terminal)

    stop.region = regions(:ulleung_eup)
    assert stop.valid?

    stop.region = regions(:gyeongnam)
    assert_not stop.valid?

    stop.region = nil
    assert_not stop.valid?

    stop.region = regions(:abolished)
    assert_not stop.valid?
  end

  test "a legacy stop can be given a region" do
    stop = stops(:legacy)

    stop.region = regions(:goseong)

    assert stop.valid?
  end

  test "an inactive region cannot be assigned to a new stop" do
    stop = Stop.new(name: "A", lat: 34.9, lng: 128.3, region: regions(:abolished))

    assert_not stop.valid?
    assert stop.errors[:region].any?
  end

  test "a stop stays valid when its region is deactivated later" do
    stop = stops(:terminal)
    regions(:goseong).update!(active: false)

    assert stops(:terminal).reload.valid?
    assert stop.reload.update(name: "이름 변경")
  end

  test "last_registered_region is the region of the newest stop in an eligible region" do
    Stop.create!(name: "울릉", lat: 37.5, lng: 130.9, region: regions(:ulleung))
    assert_equal regions(:ulleung), Stop.last_registered_region
  end

  test "last_registered_region skips inactive regions and is nil without stops" do
    Stop.create!(name: "울릉", lat: 37.5, lng: 130.9, region: regions(:ulleung))
    regions(:ulleung).update!(active: false)
    assert_equal regions(:goseong), Stop.last_registered_region

    Stop.update_all(region_id: nil)
    assert_nil Stop.last_registered_region
  end
end
