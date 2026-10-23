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
end
