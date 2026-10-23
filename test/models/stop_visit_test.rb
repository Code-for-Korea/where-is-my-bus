require "test_helper"

class StopVisitTest < ActiveSupport::TestCase
  test "open? is true until the bus exits the geofence" do
    assert stop_visits(:at_market).open?
    assert_not stop_visits(:left_terminal).open?
  end

  test "open scope returns visits without exited_at" do
    assert_equal [ stop_visits(:at_market) ], StopVisit.open.to_a
  end

  test "latest_first orders by entered_at descending" do
    assert_equal [ stop_visits(:at_market), stop_visits(:left_terminal) ], StopVisit.latest_first.to_a
  end

  test "event ids are unique so redelivered events cannot create duplicates" do
    duplicate = StopVisit.new(trip: trips(:active_one), stop: stops(:hospital), entered_at: Time.current,
                              entered_event_id: stop_visits(:at_market).entered_event_id)

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:entered_event_id, :taken)
  end

  test "event ids may be nil" do
    visit = StopVisit.new(trip: trips(:active_one), stop: stops(:hospital), entered_at: Time.current)

    assert visit.valid?
  end
end
