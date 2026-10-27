require "test_helper"

class TripFinisherTest < ActiveSupport::TestCase
  test "ends the active trip without calling Traccar" do
    result = TripFinisher.call(buses(:one))

    assert_equal trips(:active_one), result.trip
    assert_not trips(:active_one).reload.active?
    assert_not_requested :any, %r{.}
  end

  test "closes visits that are still open at the trip's end time" do
    closed_before = stop_visits(:left_terminal).exited_at

    result = TripFinisher.call(buses(:one))

    assert_not stop_visits(:at_market).reload.open?
    assert_equal result.trip.ended_at.to_f, stop_visits(:at_market).exited_at.to_f
    assert_equal closed_before.to_f, stop_visits(:left_terminal).reload.exited_at.to_f
  end

  test "a late exit event after the trip ended is ignored and leaves nothing open" do
    TripFinisher.call(buses(:one))

    result = StopVisitRecorder.call(traccar_event(type: "geofenceExit", id: 40, geofence_id: 202))

    assert_equal :no_active_trip, result.reason
    assert_empty StopVisit.where(trip: trips(:active_one)).open
  end

  test "is a no-op when the bus has no active trip" do
    result = TripFinisher.call(buses(:two))

    assert_nil result.trip
  end

  test "frees the bus to start another trip" do
    TripFinisher.call(buses(:one))

    assert_nil buses(:one).reload.active_trip
  end
end
