require "test_helper"

class StopsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @region = regions(:one)
    @route  = routes(:one)
    @target_stop = stops(:three)
  end

  test "single assigned bus with active trip and gps behaves as before" do
    RouteBus.create!(route: @route, bus: buses(:one))

    get "/r/#{@region.slug}/#{@target_stop.id}/arrival"

    body = JSON.parse(response.body)
    assert_nil body["status"]
    assert_equal 2, body["stops_away"]
    assert_equal buses(:one).bus_number, body["bus_number"]
  end

  test "no assigned buses returns no_trip" do
    get "/r/#{@region.slug}/#{@target_stop.id}/arrival"

    body = JSON.parse(response.body)
    assert_equal "no_trip", body["status"]
  end

  test "two assigned buses, neither has an active trip returns no_trip" do
    bus_one = buses(:one)
    bus_two = buses(:two)
    Trip.where(bus: [ bus_one, bus_two ]).update_all(ended_at: Time.current)
    RouteBus.create!(route: @route, bus: bus_one)
    RouteBus.create!(route: @route, bus: bus_two)

    get "/r/#{@region.slug}/#{@target_stop.id}/arrival"

    body = JSON.parse(response.body)
    assert_equal "no_trip", body["status"]
  end

  test "two assigned buses, only one has an active trip but no gps returns no_gps" do
    bus_one = buses(:one)
    bus_two = buses(:two)
    trips(:one_active).gps_logs.destroy_all
    trips(:two_active).update!(ended_at: Time.current)
    RouteBus.create!(route: @route, bus: bus_one)
    RouteBus.create!(route: @route, bus: bus_two)

    get "/r/#{@region.slug}/#{@target_stop.id}/arrival"

    body = JSON.parse(response.body)
    assert_equal "no_data", body["status"]
  end

  test "two assigned buses with active trip and gps returns the closer bus's result" do
    bus_one = buses(:one) # gps at stop 1 -> 2 stops away from stop 3
    bus_two = buses(:two) # gps at stop 2 -> 1 stop away from stop 3
    RouteBus.create!(route: @route, bus: bus_one)
    RouteBus.create!(route: @route, bus: bus_two)

    get "/r/#{@region.slug}/#{@target_stop.id}/arrival"

    body = JSON.parse(response.body)
    assert_equal 1, body["stops_away"]
    assert_equal bus_two.bus_number, body["bus_number"]
  end
end
