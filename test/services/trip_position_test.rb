require "test_helper"

# 픽스처: 1번 노선은 터미널 → 시장 → 병원. 버스 one의 운행은 터미널을 떠나 지금 시장에 정차 중이다.
class TripPositionTest < ActiveSupport::TestCase
  def names(result)
    [ result.previous&.name, result.current&.name, result.next&.name ]
  end

  test "while stopped at a stop: the stop before, the stop itself, and the stop after" do
    assert_equal [ "고성터미널", "고성시장", "고성병원" ], names(TripPosition.call(trips(:active_one)))
  end

  test "just after leaving a stop there is no current stop" do
    stop_visits(:at_market).update!(exited_at: 1.minute.ago)

    assert_equal [ "고성시장", nil, "고성병원" ], names(TripPosition.call(trips(:active_one)))
  end

  test "with no visit yet the next stop is the first stop" do
    trip = Trip.create!(bus: buses(:two), route: routes(:one), started_at: 1.minute.ago)

    assert_equal [ nil, nil, "고성터미널" ], names(TripPosition.call(trip))
  end

  test "at the first stop there is no previous stop" do
    trip = Trip.create!(bus: buses(:two), route: routes(:one), started_at: 5.minutes.ago)
    trip.stop_visits.create!(stop: stops(:terminal), entered_at: 1.minute.ago)

    assert_equal [ nil, "고성터미널", "고성시장" ], names(TripPosition.call(trip))
  end

  test "at the last stop there is no next stop" do
    stop_visits(:at_market).update!(exited_at: 3.minutes.ago)
    trips(:active_one).stop_visits.create!(stop: stops(:hospital), entered_at: 1.minute.ago)

    assert_equal [ "고성시장", "고성병원", nil ], names(TripPosition.call(trips(:active_one)))
  end

  test "to_h carries only stop names for the app" do
    assert_equal({ previous: "고성터미널", current: "고성시장", next: "고성병원" }, TripPosition.call(trips(:active_one)).to_h)
  end
end
