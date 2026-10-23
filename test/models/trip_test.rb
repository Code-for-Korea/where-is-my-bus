require "test_helper"

class TripTest < ActiveSupport::TestCase
  test "a bus cannot start a second trip while one is active" do
    trip = Trip.new(bus: buses(:one), route: routes(:two), started_at: Time.current)

    assert_not trip.valid?
    assert_includes trip.errors[:bus], "에 이미 진행 중인 운행이 있습니다"
  end

  test "the database also rejects a second active trip for the same bus" do
    duplicate = Trip.new(bus: buses(:one), route: routes(:two), started_at: Time.current)

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "a bus can start a new trip after the previous one finished" do
    assert Trip.new(bus: buses(:two), route: routes(:one), started_at: Time.current).valid?
  end

  test "finish! closes the trip and frees the bus" do
    trip = trips(:active_one)

    trip.finish!

    assert_not trip.active?
    assert_nil buses(:one).reload.active_trip
    assert Trip.create!(bus: buses(:one), route: routes(:two), started_at: Time.current)
  end

  test "active scope excludes finished trips" do
    assert_equal [ trips(:active_one) ], Trip.active.to_a
  end

  test "destroying a trip removes its visits" do
    assert_difference -> { StopVisit.count }, -2 do
      trips(:active_one).destroy
    end
  end
end
