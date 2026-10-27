require "test_helper"

class BusTest < ActiveSupport::TestCase
  test "assigns a 6-digit pin and a traccar_unique_id on create" do
    bus = Bus.create!(license_plate: "경남70가9999")

    assert_match(/\A\d{6}\z/, bus.pin)
    assert_match(/\A\h{12}\z/, bus.traccar_unique_id)
  end

  test "license_plate must be unique" do
    bus = Bus.new(license_plate: buses(:one).license_plate)

    assert_not bus.valid?
    assert bus.errors.of_kind?(:license_plate, :taken)
  end

  test "pin must be 4 to 6 digits" do
    assert_not Bus.new(license_plate: "A", pin: "123").valid?
    assert_not Bus.new(license_plate: "A", pin: "12ab56").valid?
    assert Bus.new(license_plate: "A", pin: "1234").valid?
  end

  test "regenerate_pin! issues a new pin and clears pin_registered_at" do
    bus = buses(:one)
    bus.update!(pin_registered_at: Time.current)
    old_pin = bus.pin

    bus.regenerate_pin!

    assert_not_equal old_pin, bus.pin
    assert_nil bus.pin_registered_at
  end

  test "active_trip returns the trip that has not ended" do
    assert_equal trips(:active_one), buses(:one).active_trip
    assert_nil buses(:two).active_trip
  end

  test "cannot be destroyed while it has trips" do
    bus = buses(:one)

    assert_not bus.destroy
    assert bus.errors.of_kind?(:base, :"restrict_dependent_destroy.has_many")
  end

  test "belongs to at most one route and may have none" do
    assert_equal routes(:one), buses(:one).route
    assert Bus.new(license_plate: "A", route: nil).valid?
  end

  test "the route cannot change while a trip is running" do
    bus = buses(:one)

    assert_not bus.update(route: routes(:two))
    assert_includes bus.errors[:route], "은 운행 중에는 바꿀 수 없습니다"
  end

  test "the route can change once the trip has ended" do
    trips(:active_one).finish!

    assert buses(:one).reload.update(route: routes(:two))
  end

  test "assignment_label shows where the bus is assigned" do
    assert_equal "경남70가5678 (현재: 2번 노선)", buses(:two).assignment_label
    assert_equal "A (미배정)", Bus.new(license_plate: "A").assignment_label
  end
end
