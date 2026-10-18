require "test_helper"

class MapControllerTest < ActionDispatch::IntegrationTest
  setup do
    @route = routes(:one)
    @bus = buses(:one)
    @bus.update!(traccar_unique_id: "map-test-device")
    RouteBus.find_or_create_by!(route: @route, bus: @bus)
  end

  test "노선 지도 페이지를 렌더링한다" do
    get route_map_path(id: @route.id)

    assert_response :ok
    assert_select "[data-controller='map']"
    assert_select "[data-map-provider-value='google']"
  end

  test "좌표가 없는 정류장은 제외하고 좌표가 있는 정류장은 포함한다" do
    stops_with_coords = @route.stops.select(&:coordinates?)
    get route_map_path(id: @route.id)

    assert_response :ok
    stops_with_coords.each do |stop|
      assert response.body.include?(stop.display_name)
    end
  end

  test "GPS가 있는 버스는 마커 데이터에 포함된다" do
    trip = @bus.trips.create!(started_at: 10.minutes.ago)
    GpsLog.create!(trip: trip, lat: 35.100000, lng: 128.100000, recorded_at: 1.minute.ago)
    PositionIngestor.call({ id: @bus.traccar_unique_id, lat: 35.100000, lon: 128.100000, timestamp: 1.minute.ago.to_i }, source: :osmand)

    get route_map_path(id: @route.id)

    assert_response :ok
    assert response.body.include?('"number"')
    assert response.body.include?("35.1")
  end

  test "존재하지 않는 노선은 404를 반환한다" do
    get route_map_path(id: 999_999)

    assert_response :not_found
  end
end
